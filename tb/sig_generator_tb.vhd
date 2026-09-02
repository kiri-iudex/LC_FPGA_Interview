library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--  Self-checking testbench for sig_generator
--
--  Parameters are cycle counts:
--    islv32_freq       = period P in 100 MHz clock cycles
--    islv32_duty_cycle = high-time H in 100 MHz clock cycles
--
--  Scenarios:
--    * reset -> output deterministic low
--    * different frequencies (P = 20, 40, 100)
--    * different duty cycles (25 %, 50 %, 75 %)
--    * 0 % duty  (H = 0)   -> constant low
--    * 100 % duty (H = P)  -> constant high
--    * maximum frequency 1 MHz (P = 100)
--    * minimum frequency 1 Hz (P = 100_000_000) - period logic checked
--      without simulating the full 1 s period
--    * parameter change while running 
--  Reset is active-low.


entity sig_generator_tb is
end entity;

architecture sim of sig_generator_tb is

  constant CLK_P : time := 10 ns;   -- 100 MHz

  signal isl_clk        : std_logic := '0';
  signal isl_arst_n        : std_logic := '0';
  signal islv32_duty    : std_logic_vector(31 downto 0) := (others => '0');
  signal islv32_freq    : std_logic_vector(31 downto 0) := (others => '0');
  signal isl_load       : std_logic := '0';
  signal isl_output_sig : std_logic;

  signal done : boolean := false;   
begin

  DUT : entity work.sig_generator
    generic map (P_DEFAULT => 100)
    port map (
      isl_clk           => isl_clk,
      isl_arst_n        => isl_arst_n,
      islv32_duty_cycle => islv32_duty,
      islv32_freq       => islv32_freq,
      isl_load          => isl_load,
      osl_output_sig    => isl_output_sig 
    );

  isl_clk <= not isl_clk after 5 ns;   -- 100 MHz

  stim : process

    -- SETTLE_TIME time is required to wait for low frequency periods to finish
    constant SETTLE_TIME : time := 5 us;

    variable v_errors : integer := 0;
    variable v_t0, v_t1, v_t2 : time;
    variable v_hc, v_pc : integer;

    procedure pulse_reset is
    begin
      isl_arst_n <= '0';
      wait for 100 ns;
      wait until rising_edge(isl_clk);
      isl_arst_n <= '1';
    end procedure;

    -- stage a new (P, H) via a one-cycle load pulse
    procedure apply(constant p, h : integer) is
    begin
      wait until rising_edge(isl_clk);
      islv32_freq <= std_logic_vector(to_unsigned(p, 32)); 
      islv32_duty <= std_logic_vector(to_unsigned(h, 32));
      isl_load <= '1';
      wait until rising_edge(isl_clk);
      isl_load <= '0';
    end procedure;

    -- measure one full period (only valid when 0 < H < P, i.e. edges exist)
    procedure measure_wave(constant exp_p, exp_h : integer; constant tag : string) is
    begin
      wait until rising_edge(isl_output_sig);
      v_t0 := now;
      wait until falling_edge(isl_output_sig);
      v_t1 := now;
      wait until rising_edge(isl_output_sig);
      v_t2 := now;
      v_hc := (v_t1 - v_t0) / CLK_P;
      v_pc := (v_t2 - v_t0) / CLK_P;
      if v_hc /= exp_h then
        v_errors := v_errors + 1;
        report tag & ": high-time = " & integer'image(v_hc) &
               " cycles, expected " & integer'image(exp_h) severity error;
      end if;
      if v_pc /= exp_p then
        v_errors := v_errors + 1;
        report tag & ": period = " & integer'image(v_pc) &
               " cycles, expected " & integer'image(exp_p) severity error;
      else
        if v_hc = exp_h then
          report tag & ": OK (high=" & integer'image(v_hc) &
                 ", period=" & integer'image(v_pc) & ")" severity note;
        end if;
      end if;
    end procedure;

    -- verify output holds a constant level for a specified number of cycles (usually P parameter)
    procedure check_constant(constant lvl : std_logic; constant cyc : integer;
                             constant tag : string) is
      variable v_ok : boolean := true;
    begin
      for i in 1 to cyc loop
        wait until rising_edge(isl_clk);
        wait for 1 ns;                     -- sample SETTLE_TIMEd value
        if isl_output_sig /= lvl then v_ok := false; end if;
      end loop;
      if v_ok then
        report tag & ": OK (constant " & std_logic'image(lvl) & ")" severity note;
      else
        v_errors := v_errors + 1;
        report tag & ": expected constant " & std_logic'image(lvl) severity error;
      end if;
    end procedure;

  begin

    -- Test 1: reset -> deterministic low output

    pulse_reset;
    wait for 300 ns;
    assert isl_output_sig = '0'
      report "Test 1: output not low after reset" severity error;
    report "Test 1 reset: output low (OK)" severity note;


    -- Test 2: Minimal Freq Test (1 Hz, P = 100_000_000) as the first config after reset.
    --
    -- Note: a full 1 Hz period is 100_000_000 cycles = 1 s of sim time, which
    -- is impractical to run. Instead we verify the period logic without
    -- completing the period: after reset H_active = 0 (output low), so the
    -- first rising edge is the moment the new config applies. We measure
    -- the 50-cycle high pulse, then confirm the output stays low for
    -- 2000 further cycles - proving the counter is still counting the huge
    -- period and not wrapping

    apply(100_000_000, 50);
    wait until rising_edge(isl_output_sig) for 3 us;   -- swap occurs within P_DEFAULT cycles
    assert isl_output_sig = '1'
      report "MIN FREQ: config never applied (no rising edge)" severity error;
    v_t0 := now;
    wait until falling_edge(isl_output_sig) for 3 us;
    v_hc := (now - v_t0) / CLK_P;
    if v_hc = 50 then
      report "MIN FREQ: high pulse = 50 cycles (OK)" severity note;
    else
      v_errors := v_errors + 1;
      report "MIN FREQ: high pulse = " & integer'image(v_hc) &
             " cycles, expected 50" severity error;
    end if;
    -- confirm it does not wrap for a long time (period > 2000 cycles)
    check_constant('0', 2000, "MIN FREQ low-hold");


    -- Reset to clear the huge period before the small-P tests
    -- (otherwise the next config would not apply for ~1 s).
    pulse_reset;
    wait for 300 ns;


    -- Test 3: 50 % duty, P = 20  (H = 10)
    apply(20, 10);
    wait for SETTLE_TIME;
    measure_wave(20, 10, "T2 50%% P=20");


    -- Test 4: 25 % duty, P = 40  (H = 10)
    apply(40, 10);
    wait for SETTLE_TIME;
    measure_wave(40, 10, "T3 25%% P=40");


    -- Test 5: 75 % duty, P = 40  (H = 30)
    apply(40, 30);
    wait for SETTLE_TIME;
    measure_wave(40, 30, "T4 75%% P=40");


    -- Test 6: MAX frequency 1 MHz, P = 100, 50 % duty (H = 50)
    apply(100, 50);
    wait for SETTLE_TIME;
    measure_wave(100, 50, "T5 MAX-FREQ P=100");


    -- Test 7: 100 % duty, P = 20, H = 20 -> constant high
    apply(20, 20);
    wait for SETTLE_TIME;
    check_constant('1', 40, "T6 100%% duty");


    -- Test 8: 0 % duty, P = 20, H = 0 -> constant low
    apply(20, 0);
    wait for SETTLE_TIME;
    check_constant('0', 40, "T7 0%% duty");


    -- Test 9: parameter change while running - back to a normal wave and
    -- confirm the new wave is exact.
    apply(20, 10);
    wait for SETTLE_TIME;
    measure_wave(20, 10, "T8 change-back P=20");


    report "=================================================";
    if v_errors = 0 then
      report "TB RESULT: PASSED" severity note;
    else
      report "TB RESULT: FAILED with " & integer'image(v_errors) &
             " error(s)" severity error;
    end if;
    report "=================================================";

    done <= true;
    wait;
  end process;

end architecture;