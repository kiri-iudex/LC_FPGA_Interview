library ieee;
use ieee.std_logic_1164.all;

entity sync_2ff is
  port (
    isl_clk   : in  std_logic;          -- destination-domain clock
    isl_rst : in  std_logic;            -- async assert, sync de-assert (active low)
    isl_d  : in  std_logic;             -- single bit from the source domain
    osl_d : out std_logic               -- synchronized bit in the destination domain
  );
end entity sync_2ff;

architecture rtl of sync_2ff is
  signal slv2_sync_ff : std_logic_vector(1 downto 0); -- 2FF sync vector. Generic can be added to increase the depth of the vector and counter act the metastability even further

begin
  process(isl_clk, isl_rst)
  begin
    if isl_rst = '0' then
      slv2_sync_ff <= (others => '0');
    elsif rising_edge(isl_clk) then
      slv2_sync_ff(0) <= isl_d;         -- 1st stage: metastability possbile
      slv2_sync_ff(1) <= slv2_sync_ff(0);   -- 2nd stage: stable signal
    end if;
  end process;

  osl_d <= slv2_sync_ff(1);
end architecture rtl;