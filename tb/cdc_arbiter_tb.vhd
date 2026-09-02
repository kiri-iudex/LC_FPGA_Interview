library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--  Self-checking testbench for cdc_arbiter
--
--  Covers the CDC-relevant tests from the task's section 7:
--    * asynchronous 33 MHz -> 100 MHz parameter transfer
--    * reset behaviour 
--    * single parameter change
--    * multiple / back-to-back parameter changes
--    * configuration coherency - all four params cross together
--    * one osl_load pulse per commit
--    * commit ignored while a transfer is in progress

entity cdc_arbiter_tb is
end entity;

architecture sim of cdc_arbiter_tb is


  signal isl_clk100, isl_clk33 : std_logic := '0';
  signal isl_arst100_n, isl_arst33_n : std_logic := '0';

  signal islv32_freq0, islv32_duty0, islv32_freq1, islv32_duty1 : std_logic_vector(31 downto 0) := (others => '0');
  signal isl_commit33 : std_logic := '0';

  signal oslv32_freq0, oslv32_duty0, oslv32_freq1, oslv32_duty1 : std_logic_vector(31 downto 0);
  signal osl_load, osl_busy : std_logic;

  signal sim_done   : boolean := false;
  signal load_count : integer := 0;   -- total one-cycle osl_load pulses

begin

  DUT : entity work.cdc_arbiter
    port map (
      isl_clk100    => isl_clk100,   isl_clk33     => isl_clk33,
      isl_arst100_n    => isl_arst100_n,   isl_arst33_n     => isl_arst33_n,
      islv32_freq_ch0 => islv32_freq0, islv32_duty_ch0 => islv32_duty0,
      islv32_freq_ch1 => islv32_freq1, islv32_duty_ch1 => islv32_duty1,
      isl_commit33  => isl_commit33,
      oslv32_freq_ch0 => oslv32_freq0, oslv32_duty_ch0 => oslv32_duty0,
      oslv32_freq_ch1 => oslv32_freq1, oslv32_duty_ch1 => oslv32_duty1,
      osl_load      => osl_load,      osl_busy      => osl_busy
    );

    isl_clk100 <= not isl_clk100 after 5 ns;   -- 100 MHz
    isl_clk33 <= not isl_clk33 after 15.15 ns;    -- ~33Mhz


  -- Detect the osl_load signal pulse
  load_monitor : process (isl_clk100)
  begin
    if rising_edge(isl_clk100) then
      if osl_load = '1' then
        load_count <= load_count + 1;
      end if;
    end if;
  end process;


  stim : process

    variable v_errors       : integer := 0;
    variable v_loads_before : integer := 0;

    -- Helper function
    -- Drive one commit in the 33 MHz domain and wait for the handshake to complete.
    procedure do_commit(
      constant f0, d0, f1, d1 : in std_logic_vector(31 downto 0)
    ) is
    begin
      if osl_busy = '1' then
        wait until osl_busy = '0';
      end if;
      wait until rising_edge(isl_clk33);
      islv32_freq0 <= f0; islv32_duty0 <= d0; islv32_freq1 <= f1; islv32_duty1 <= d1;
      isl_commit33 <= '1';
      v_loads_before := load_count;
      wait until rising_edge(isl_clk33);
      isl_commit33 <= '0';
      wait until osl_busy = '1' for 2 us;
      assert osl_busy = '1' report "osl_busy never asserted after commit" severity error;
      wait until osl_busy = '0' for 5 us;
      assert osl_busy = '0' report "handshake did not complete (osl_busy stuck)" severity error;
      wait until rising_edge(isl_clk33); 
    end procedure;
    
    -- Helper function
    -- Compare outputs with sent data
    procedure check_outputs(
      constant f0, d0, f1, d1 : in std_logic_vector(31 downto 0);
      constant tag            : in string
    ) is
    begin
      if oslv32_freq0 /= f0 then
        v_errors := v_errors + 1;
        report tag & ": freq0 mismatch" severity error;
      end if;
      if oslv32_duty0 /= d0 then
        v_errors := v_errors + 1;
        report tag & ": duty0 mismatch" severity error;
      end if;
      if oslv32_freq1 /= f1 then
        v_errors := v_errors + 1;
        report tag & ": freq1 mismatch" severity error;
      end if;
      if oslv32_duty1 /= d1 then
        v_errors := v_errors + 1;
        report tag & ": duty1 mismatch" severity error;
      end if;
    end procedure;

    procedure check_single_load(constant tag : in string) is
    begin
      if (load_count - v_loads_before) /= 1 then
        v_errors := v_errors + 1;
        report tag & ": expected exactly one osl_load pulse, got " &
               integer'image(load_count - v_loads_before) severity error;
      end if;
    end procedure;

  begin

    -- Test 1: Reset behaviour
    isl_arst100_n <= '0'; isl_arst33_n <= '0';
    for i in 0 to 9 loop wait until rising_edge(isl_clk100); end loop;
    assert osl_load = '0' report "T1: osl_load asserted during reset" severity error;
    assert osl_busy = '0' report "T1: osl_busy asserted during reset" severity error;
    if load_count /= 0 then
      v_errors := v_errors + 1;
      report "T1: spurious osl_load during reset" severity error;
    end if;
    -- release reset
    wait until rising_edge(isl_clk33);  isl_arst33_n  <= '1';
    wait until rising_edge(isl_clk100); isl_arst100_n <= '1';
    for i in 0 to 9 loop wait until rising_edge(isl_clk100); end loop;

    -- Test 2: Basic transfer
    do_commit(x"00000064", x"00000032", x"000003E8", x"00000019");                 -- osl_load = 1
    check_outputs(x"00000064", x"00000032", x"000003E8", x"00000019", "T2 basic");
    check_single_load("T2 basic");

  
    -- Test 3: Different parameters
    do_commit(x"12345678", x"9ABCDEF0", x"0F0F0F0F", x"F0F0F0F0");                -- osl_load = 2
    check_outputs(x"12345678", x"9ABCDEF0", x"0F0F0F0F", x"F0F0F0F0", "T3 change");
    check_single_load("T3 change");

 
    -- Test 4: Edge values
    do_commit(x"00000000", x"00000000", x"00000000", x"00000000");                -- osl_load = 3
    check_outputs(x"00000000", x"00000000", x"00000000", x"00000000", "T4 zeros");
    check_single_load("T4 zeros");

    do_commit(x"FFFFFFFF", x"FFFFFFFF", x"FFFFFFFF", x"FFFFFFFF");                -- osl_load = 4
    check_outputs(x"FFFFFFFF", x"FFFFFFFF", x"FFFFFFFF", x"FFFFFFFF", "T4 ones");
    check_single_load("T4 ones");


    -- Test 5: Coherency - four distinct values must not mix
    do_commit(x"AAAAAAAA", x"BBBBBBBB", x"CCCCCCCC", x"DDDDDDDD");                -- osl_load = 5
    check_outputs(x"AAAAAAAA", x"BBBBBBBB", x"CCCCCCCC", x"DDDDDDDD", "T5 coherency");
    check_single_load("T5 coherency");


    -- Test 6: Back-to-back transfers
    do_commit(x"00000001", x"00000002", x"00000003", x"00000004");                -- osl_load = 6
    check_outputs(x"00000001", x"00000002", x"00000003", x"00000004", "T6a");
    check_single_load("T6a");
    do_commit(x"00000005", x"00000006", x"00000007", x"00000008");                -- osl_load = 7
    check_outputs(x"00000005", x"00000006", x"00000007", x"00000008", "T6b");
    check_single_load("T6b");


    -- Test 7: Commit while when CDC is osl_busy -> output should have the original commit data
    if osl_busy = '1' then wait until osl_busy = '0'; end if;
    wait until rising_edge(isl_clk33);
    islv32_freq0 <= x"10000000"; islv32_duty0 <= x"20000000";
    islv32_freq1 <= x"30000000"; islv32_duty1 <= x"40000000";
    isl_commit33 <= '1';                                                              -- osl_load = 8
    v_loads_before := load_count;
    wait until rising_edge(isl_clk33);
    isl_commit33 <= '0';
    wait until osl_busy = '1' for 2 us;

    -- false commit 
    wait until rising_edge(isl_clk33);
    islv32_freq0 <= x"DEADBEEF";
    isl_commit33 <= '1';                                                               -- osl_load counter will not increment, as this is a false commit
    wait until rising_edge(isl_clk33);
    isl_commit33 <= '0';
    wait until osl_busy = '0' for 5 us;
    assert osl_busy = '0' report "T7: handshake stuck" severity error;
    wait until rising_edge(isl_clk33);
    check_outputs(x"10000000", x"20000000", x"30000000", x"40000000", "T7 backpressure");
    if (load_count - v_loads_before) /= 1 then
      v_errors := v_errors + 1;
      report "T7 backpressure: expected exactly one osl_load, got " &
             integer'image(load_count - v_loads_before) severity error;
    end if;


    -- Report
    wait for 500 ns;
    report "=================================================";
    if v_errors = 0 then
      report "TB RESULT: PASSED  (total osl_load pulses = " &
             integer'image(load_count) & ")" severity note;
    else
      report "TB RESULT: FAILED with " & integer'image(v_errors) &
             " error(s)" severity error;
    end if;
    report "=================================================";

    sim_done <= true;
    wait;
  end process;

end architecture sim;