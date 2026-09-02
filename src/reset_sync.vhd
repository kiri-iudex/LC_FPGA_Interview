library ieee;
use ieee.std_logic_1164.all;
use IEEE.NUMERIC_STD.ALL;

-------------------------------------------------------------------------------
-- File        : reset_sync.vhd
-- Project     : Two-Channel Signal Generator with CDC
-- Author      : Kiril Burlakov
-- Standard    : VHDL
-------------------------------------------------------------------------------
-- Description : Reset synchronizer providing an asynchronous-assert, synchronous-de-assert
--               reset. It takes a raw external asynchronous active-low reset and produces
--               a clean, domain-local reset: assertion is immediate (no clock required),
--               while de-assertion is re-timed to the local clock by shifting through two
--               flip-flops. One instance is used per clock domain so each domain leaves
--               reset cleanly and avoids recovery/removal timing problems on release.
-------------------------------------------------------------------------------

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