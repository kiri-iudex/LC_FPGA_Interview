library ieee;
use ieee.std_logic_1164.all;
use IEEE.NUMERIC_STD.ALL;

-- Async assert, sync de-assert
entity reset_sync is
  port (
    isl_clk         : in  std_logic;
    isl_async_rst_n : in  std_logic;     
    osl_rst_n       : out std_logic          
  );
end entity;

architecture rtl of reset_sync is
  signal slv2_ff : std_logic_vector(1 downto 0);
begin
  process(isl_clk, isl_async_rst_n)
  begin
    if isl_async_rst_n = '0' then          -- asynchronous assert
      slv2_ff <= (others => '0');
    elsif rising_edge(isl_clk) then        -- synchronous de-assert, delayed to avoid metastability
      slv2_ff(0) <= '1';
      slv2_ff(1) <= slv2_ff(0);
    end if;
  end process;

  osl_rst_n <= slv2_ff(1);
end architecture;