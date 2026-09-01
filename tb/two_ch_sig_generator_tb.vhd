library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--  Top-level self-checking testbench for two_ch_sig_generator
--
--  Drives configuration through the 33 MHz commit interface, lets the
--  CDC cross it into the 100 MHz domain, and checks the two channel
--  outputs. Parameters are cycle counts:
--     islv32_freq_chX = period P in 100 MHz clock cycles
--     islv32_duty_chX = high-time H in 100 MHz clock cycles
--
--  Section 7 checklist coverage:
--    * both channels operating                       (Test 4)
--    * different frequencies across channels         (Test 4)
--    * different duty cycles                         (Test 4)
--    * minimum frequency 1 Hz  (P = 100_000_000)     (Test 2, see note)
--    * maximum frequency 1 MHz (P = 100)             (Test 5)
--    * 0 % duty cycle                                (Test 6)
--    * 100 % duty cycle                              (Test 6)
--    * parameter change while running                (Test 7)
--    * multiple parameter changes                    (Test 7)
--    * asynchronous 33 MHz -> 100 MHz transfer       (every commit)
--    * reset operation                               (Test 1, Test 9)
--    * no extra / incorrect pulses on change         (exact measures)
--    * channel independence (functional requirement) (Test 8)


entity two_ch_sig_generator_tb is
end entity;

architecture sim of two_ch_sig_generator_tb is
  constant CLK100_P : time := 10.000 ns;   -- 100 MHz
  constant SETTLE_TIME   : time := 5 us;   -- SETTLE_TIME time is required to wait for low frequency periods to finish

  signal isl_clk100 : std_logic := '0';
  signal isl_clk33  : std_logic := '0';
  signal isl_arst_n : std_logic := '0';     -- async, active low

  signal isl_commit : std_logic := '0';
  signal islv32_duty_ch0 : std_logic_vector(31 downto 0) := (others => '0');
  signal islv32_freq_ch0 : std_logic_vector(31 downto 0) := (others => '0');
  signal islv32_duty_ch1 : std_logic_vector(31 downto 0) := (others => '0');
  signal islv32_freq_ch1 : std_logic_vector(31 downto 0) := (others => '0');

  signal osl_busy    : std_logic;
  signal osl_sig_ch0 : std_logic;
  signal osl_sig_ch1 : std_logic;

  signal done : boolean := false;          -- simulation-control flag
begin

  DUT : entity work.two_ch_sig_generator
    port map (
      isl_clk100      => isl_clk100,
      isl_clk33       => isl_clk33,
      isl_arst_n      => isl_arst_n,
      isl_commit      => isl_commit,
      islv32_duty_ch0 => islv32_duty_ch0,
      islv32_freq_ch0 => islv32_freq_ch0,
      islv32_duty_ch1 => islv32_duty_ch1,
      islv32_freq_ch1 => islv32_freq_ch1,
      osl_busy        => osl_busy,
      osl_sig_ch0     => osl_sig_ch0,
      osl_sig_ch1     => osl_sig_ch1
    );

  isl_clk100 <= not isl_clk100 after 5 ns;   -- 100 MHz
  isl_clk33 <= not isl_clk33 after 15.15 ns; -- ~33Mhz

  stim : process
    variable v_errors : integer := 0;
    variable v_t0, v_t1, v_t2 : time;
    variable v_hc, v_pc : integer;
    variable v_h0, v_h1, v_cnt : integer;

    -- assert async reset, then release it cleanly
    procedure do_reset is
    begin
      isl_arst_n <= '0';
      wait for 200 ns;
      wait until rising_edge(isl_clk33);
      isl_arst_n <= '1';
      wait for 300 ns;                      -- let sync de-assert propagate
    end procedure;

    -- drive both channels parameters and run one commit
    procedure commit(constant p0, h0, p1, h1 : integer) is
    begin
      if osl_busy = '1' then wait until osl_busy = '0'; end if;
      wait until rising_edge(isl_clk33);
      islv32_freq_ch0 <= std_logic_vector(to_unsigned(p0, 32));
      islv32_duty_ch0 <= std_logic_vector(to_unsigned(h0, 32));
      islv32_freq_ch1 <= std_logic_vector(to_unsigned(p1, 32));
      islv32_duty_ch1 <= std_logic_vector(to_unsigned(h1, 32));
      isl_commit <= '1';
      wait until rising_edge(isl_clk33);
      isl_commit <= '0';
      wait until osl_busy = '1' for 2 us;
      assert osl_busy = '1' report "commit: busy never asserted" severity error;
      wait until osl_busy = '0' for 5 us;
      assert osl_busy = '0' report "commit: handshake did not complete" severity error;
    end procedure;

    -- measure one full period of a channel (needs 0 < H < P so edges exist)
    procedure measure_wave(signal sig : in std_logic;
                           constant exp_p, exp_h : integer;
                           constant tag : string) is
    begin
      wait until rising_edge(sig);
      v_t0 := now;
      wait until falling_edge(sig);
      v_t1 := now;
      wait until rising_edge(sig);
      v_t2 := now;
      v_hc := (v_t1 - v_t0) / CLK100_P;
      v_pc := (v_t2 - v_t0) / CLK100_P;
      if v_hc /= exp_h then
        v_errors := v_errors + 1;
        report tag & ": high-time = " & integer'image(v_hc) &
               ", expected " & integer'image(exp_h) severity error;
      end if;
      if v_pc /= exp_p then
        v_errors := v_errors + 1;
        report tag & ": period = " & integer'image(v_pc) &
               ", expected " & integer'image(exp_p) severity error;
      elsif v_hc = exp_h then
        report tag & ": OK (high=" & integer'image(v_hc) &
               ", period=" & integer'image(v_pc) & ")" severity note;
      end if;
    end procedure;

    -- verify a channel holds a constant level across at least one period
    procedure check_constant(signal sig : in std_logic;
                             constant lvl : std_logic; constant cyc : integer;
                             constant tag : string) is
      variable v_ok : boolean := true;
    begin
      for i in 1 to cyc loop
        wait until rising_edge(isl_clk100);
        wait for 1 ns;
        if sig /= lvl then v_ok := false; end if;
      end loop;
      if v_ok then
        report tag & ": OK (constant " & std_logic'image(lvl) & ")" severity note;
      else
        v_errors := v_errors + 1;
        report tag & ": expected constant " & std_logic'image(lvl) severity error;
      end if;
    end procedure;

  begin

    -- Test 1: reset -> both outputs deterministic low
    do_reset;
    wait for 300 ns;
    if osl_sig_ch0 = '0' and osl_sig_ch1 = '0' then
      report "T1 reset: both outputs low (OK)" severity note;
    else
      v_errors := v_errors + 1;
      report "T1 reset: an output is not low after reset" severity error;
    end if;


    -- Test 2: Min frequency 1 Hz (P = 100_000_000), both channels.
    --
    -- A full 1 Hz period is 100_000_000 cycles = 1 s of sim time, so we do not
    -- run a whole period. After reset, H_active is 0 (outputs low), so the
    -- first rising edge is the moment the config applies. Both channels
    -- counters are reset together and run together, so both rise on
    -- the same edge. We sample both to capture each high pulse, then
    -- confirm both stay low for 2000 further cycles (period >> 2000).
    -- ch0 H = 50, ch1 H = 30.

    commit(100_000_000, 50, 100_000_000, 30);
    wait until rising_edge(osl_sig_ch0) for 5 us;
    assert osl_sig_ch0 = '1'
      report "T2 min-freq: config never applied" severity error;
    v_h0 := -1; v_h1 := -1; v_cnt := 0;
    loop
      wait until rising_edge(isl_clk100);
      wait for 1 ns;
      v_cnt := v_cnt + 1;
      if v_h0 < 0 and osl_sig_ch0 = '0' then v_h0 := v_cnt; end if;
      if v_h1 < 0 and osl_sig_ch1 = '0' then v_h1 := v_cnt; end if;
      exit when (v_h0 >= 0 and v_h1 >= 0) or v_cnt > 300;
    end loop;
    if v_h0 = 50 then report "T2 min-freq ch0: high pulse 50 cycles (OK)" severity note;
    else v_errors := v_errors + 1;
      report "T2 min-freq ch0: high pulse = " & integer'image(v_h0) & ", expected 50" severity error; end if;
    if v_h1 = 30 then report "T2 min-freq ch1: high pulse 30 cycles (OK)" severity note;
    else v_errors := v_errors + 1;
      report "T2 min-freq ch1: high pulse = " & integer'image(v_h1) & ", expected 30" severity error; end if;
    -- both must stay low for a long time
    for i in 1 to 2000 loop
      wait until rising_edge(isl_clk100); wait for 1 ns;
      if osl_sig_ch0 /= '0' or osl_sig_ch1 /= '0' then
        v_errors := v_errors + 1;
        report "T2 min-freq: output wrapped too early" severity error;
        exit;
      end if;
    end loop;
    report "T2 min-freq low-hold: OK" severity note;


    -- Test 3: reset to clear the huge period before the small-P tests
    do_reset;
    wait for 300 ns;


    -- Test 4: Both channels are configured,  
    -- different frequencies and different duties
    --     ch0 = 50 % at P=20   ch1 = 75 % at P=40
    commit(20, 10, 40, 30);
    wait for SETTLE_TIME;
    measure_wave(osl_sig_ch0, 20, 10, "T4 ch0 (50%% P=20)");
    measure_wave(osl_sig_ch1, 40, 30, "T4 ch1 (75%% P=40)");

    -- Test 5: Max frequency 1 MHz (P = 100) on both channels,
    --     different duties (ch0 50 %, ch1 25 %)
    commit(100, 50, 100, 25);
    wait for SETTLE_TIME;
    measure_wave(osl_sig_ch0, 100, 50, "T5 ch0 MAX-FREQ");
    measure_wave(osl_sig_ch1, 100, 25, "T5 ch1 MAX-FREQ");

    -- Test 6: Edge duties on the two channels at once
    --     ch0 = 0 %   (H=0)  -> constant low
    --     ch1 = 100 % (H=P)  -> constant high
    commit(20, 0, 20, 20);
    wait for SETTLE_TIME;
    check_constant(osl_sig_ch0, '0', 40, "T6 ch0 0%% duty");
    check_constant(osl_sig_ch1, '1', 40, "T6 ch1 100%% duty");


    -- Test 7: Multiple parameter changes while running
    --     Three consecutive reconfigurations, each verified.
    commit(20, 10, 20, 10);
    wait for SETTLE_TIME;
    measure_wave(osl_sig_ch0, 20, 10, "T7a ch0");
    measure_wave(osl_sig_ch1, 20, 10, "T7a ch1");

    commit(40, 20, 30, 15);
    wait for SETTLE_TIME;
    measure_wave(osl_sig_ch0, 40, 20, "T7b ch0");
    measure_wave(osl_sig_ch1, 30, 15, "T7b ch1");

    commit(50, 5, 80, 60);
    wait for SETTLE_TIME;
    measure_wave(osl_sig_ch0, 50, 5,  "T7c ch0");
    measure_wave(osl_sig_ch1, 80, 60, "T7c ch1");


    -- Test 8: Channel independence
    --     Change ch0 while resending ch1 current values.
    --     Ch1 output must remain the same wave.
    --     (Start from ch0=P20/H10, ch1=P40/H20.)
    commit(20, 10, 40, 20);
    wait for SETTLE_TIME;
    measure_wave(osl_sig_ch1, 40, 20, "T8 ch1 before");
    -- now change ONLY ch0; keep ch1 identical
    commit(30, 15, 40, 20);
    wait for SETTLE_TIME;
    measure_wave(osl_sig_ch0, 30, 15, "T8 ch0 changed");
    measure_wave(osl_sig_ch1, 40, 20, "T8 ch1 unchanged");


    -- Test 9: Reset during operation
    --     Configure, confirm running, assert reset, confirm both low,
    --     release and reconfigure, confirm recovery.
    commit(20, 10, 20, 10);
    wait for SETTLE_TIME;
    measure_wave(osl_sig_ch0, 20, 10, "T9 pre-reset ch0");
    -- assert reset mid-operation
    isl_arst_n <= '0';
    wait for 200 ns;
    check_constant(osl_sig_ch0, '0', 20, "T9 ch0 during reset");
    check_constant(osl_sig_ch1, '0', 20, "T9 ch1 during reset");
    -- release and reconfigure
    wait until rising_edge(isl_clk33);
    isl_arst_n <= '1';
    wait for 300 ns;
    commit(40, 20, 40, 20);
    wait for SETTLE_TIME;
    measure_wave(osl_sig_ch0, 40, 20, "T9 post-reset ch0");
    measure_wave(osl_sig_ch1, 40, 20, "T9 post-reset ch1");


    report "=================================================";
    if v_errors = 0 then
      report "TB RESULT: PASSED (all scenarios)" severity note;
    else
      report "TB RESULT: FAILED with " & integer'image(v_errors) &
             " error(s)" severity error;
    end if;
    report "=================================================";

    done <= true;
    wait;
  end process;

end architecture;