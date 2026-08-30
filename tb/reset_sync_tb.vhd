library ieee;
use ieee.std_logic_1164.all;

--  Self-checking testbench for reset_sync
--
--  Verifies the two main properties of the reset synchronizer:
--    1) Asynchrounous Assert   - osl_rst_n goes low immediately when isl_async_rst_n
--                               drops, without waiting for a clock edge.
--    2) Synchrounous Deassert  - after isl_async_rst_n is released, osl_rst_n stays
--                               low for exactly 2 clock edges, then rises
--                               synchronously with the clock.

entity reset_sync_tb is
end entity;

architecture sim of reset_sync_tb is

  signal isl_clk         : std_logic := '0';
  signal isl_async_rst_n : std_logic := '1';
  signal osl_rst_n       : std_logic;
begin

  DUT : entity work.reset_sync
    port map (isl_clk => isl_clk, isl_async_rst_n => isl_async_rst_n, osl_rst_n => osl_rst_n);

    isl_clk <= not isl_clk after 5 ns;   -- 100 MHz

  stim : process
    variable v_errors : integer := 0;
    variable v_edges  : integer;
  begin

    -- Start with reset asserted, then release and count edges to de-assertion (expect exactly 2).
    isl_async_rst_n <= '0';
    wait for 23 ns;
    
    -- Check if the output of the reset synchronizer is '0'
    assert osl_rst_n = '0'
      report "reset asserted but osl_rst_n /= 0" severity error;

    -- Release reset while clock is low, so it is stable before the next rising edge
    wait until falling_edge(isl_clk);
    isl_async_rst_n <= '1';

    -- Count rising edges until output goes high and sample with 1 ns after each rising edge of the clock to read a settled FF value 
    v_edges := 0;
    loop
      wait until rising_edge(isl_clk);
      wait for 1 ns;
      v_edges := v_edges + 1;
      exit when osl_rst_n = '1';
      if v_edges > 10 then
        v_errors := v_errors + 1;
        report "de-assert never happened" severity error;
        exit;
      end if;
    end loop;

    if v_edges = 2 then
      report "Synchrounous de-assert: released after exactly 2 clock edges (correct)" severity note;
    else
      v_errors := v_errors + 1;
      report "Synchrounous de-assert: expected 2 edges, got " &
             integer'image(v_edges) severity error;
    end if;

    -- Let it run and check if the output is still '1'
    wait for 100 ns;
    assert osl_rst_n = '1'
      report "osl_rst_n should stay high after de-assert" severity error;


    -- Asynchrounous Assert: assert reset deliberately between clock edges and check if the output follows immediately
    wait until falling_edge(isl_clk);          
    wait for 2 ns;                         
    isl_async_rst_n <= '0';
    wait for 1 ns;

    if osl_rst_n = '0' then
      report "Asynchrounous Assert: osl_rst_n dropped immediately, no clock edge (correct)" severity note;
    else
      v_errors := v_errors + 1;
      report "Asynchrounous Assert: osl_rst_n did not follow isl_async_rst_n immediately" severity error;
    end if;

    -- Release again and confirm 2-edge de-assert once more
    wait until falling_edge(isl_clk);
    isl_async_rst_n <= '1';
    v_edges := 0;
    loop
      wait until rising_edge(isl_clk);
      wait for 1 ns;
      v_edges := v_edges + 1;
      exit when osl_rst_n = '1';
      exit when v_edges > 10;
    end loop;
    if v_edges /= 2 then
      v_errors := v_errors + 1;
      report "second de-assert: expected 2 edges, got " &
             integer'image(v_edges) severity error;
    end if;


    report "=================================================";
    if v_errors = 0 then
      report "TB RESULT: PASSED" severity note;
    else
      report "TB RESULT: FAILED with " & integer'image(v_errors) &
             " error(s)" severity error;
    end if;
    report "=================================================";
    wait;
  end process;

end architecture;