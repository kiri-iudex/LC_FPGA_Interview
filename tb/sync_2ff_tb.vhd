library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sync_2ff_tb is
end sync_2ff_tb;

architecture sim of sync_2ff_tb is
  signal isl_clk100 : std_logic := '0';
  signal isl_rst100 : std_logic := '0';
  signal isl_clk33  : std_logic := '0';
  signal isl_rst33  : std_logic := '0';

  signal isl_d33  : std_logic := '0';   
  signal isl_d100 : std_logic := '0';   
  signal osl_d100 : std_logic;          
  signal osl_d33  : std_logic;          
begin

  isl_clk100 <= not isl_clk100 after 5 ns;   -- 100 MHz
  isl_clk33  <= not isl_clk33  after 15 ns;  -- ~33 MHz  

  -- synchronize a 33-domain bit INTO the 100 MHz domain
  DUT_100 : entity work.sync_2ff
    port map (
      isl_clk => isl_clk100,   
      isl_rst => isl_rst100,
      isl_d   => isl_d33,
      osl_d   => osl_d100
    );

  -- synchronize a 100-domain bit INTO the 33 MHz domain
  DUT_33 : entity work.sync_2ff
    port map (
      isl_clk => isl_clk33,
      isl_rst => isl_rst33,
      isl_d   => isl_d100,
      osl_d   => osl_d33
    );

  SEQUENCER_PROC : process
  begin
    isl_rst100 <= '0';
    isl_rst33  <= '0';
    wait for 50 ns;
    isl_rst100 <= '1';
    isl_rst33  <= '1';

    wait for 100 ns;
    isl_d33 <= '1';           -- drive a bit, watch it appear on osl_d100 after 2 clocks
    wait for 100 ns;
    isl_d33 <= '0';
    wait for 100 ns;

    isl_d100 <= '1';           -- drive a bit, watch it appear on osl_d33 after 2 clocks
    wait for 100 ns;
    isl_d100 <= '0';
    wait for 100 ns;

    report "Testbench finished: OK" severity note;
    wait;
  end process;

end architecture;