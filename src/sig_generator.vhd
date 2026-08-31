library ieee;
use ieee.std_logic_1164.all;
use IEEE.NUMERIC_STD.ALL;


entity sig_generator is
  generic (
    P_DEFAULT : natural range 100 to 100_000_000 := 100                 -- Default frequency of the signal generator. Cannot be outside of the [1Hz - 1MHz] range.
  );
  port (
    isl_clk           : in std_logic;
    isl_rst           : in std_logic;
    islv32_duty_cycle : in std_logic_vector(31 downto 0);
    islv32_freq       : in std_logic_vector(31 downto 0);
    isl_load          : in std_logic;
    
    osl_output_sig    : out std_logic
  );
end sig_generator;
  
architecture rtl of sig_generator is
  signal sl_count_pwm : std_logic_vector (31 downto 0) := (others => '0');
  signal sl_period_end : std_logic := '0';

  signal sl_P_active : std_logic_vector (31 downto 0) := std_logic_vector(to_unsigned(P_DEFAULT, 32));
  signal sl_H_active : std_logic_vector (31 downto 0) := (others => '0');

  signal sl_P_pending : std_logic_vector (31 downto 0) := std_logic_vector(to_unsigned(P_DEFAULT, 32));
  signal sl_H_pending : std_logic_vector (31 downto 0) := (others => '0');

  signal sl_update_ready : std_logic := '0';
begin

  -- Process responsible for updating the comparison registers.
  update_proc : process(isl_clk, isl_rst)
  begin
      if isl_rst = '0' then
        sl_update_ready <= '0';
        sl_P_active <= std_logic_vector(to_unsigned(P_DEFAULT, 32));
        sl_H_active <= (others => '0');
        sl_P_pending <= std_logic_vector(to_unsigned(P_DEFAULT, 32));
        sl_H_pending <= (others => '0');

      elsif rising_edge(isl_clk) then
        -- If a data update is available and the signal generator has finshed outputting one period => load the new config data into the comparison registers and deassert the update flag.
        if sl_update_ready = '1' and sl_period_end = '1' then
          sl_P_active <= sl_P_pending;
          sl_H_active <= sl_H_pending;
          sl_update_ready <= '0';
        end if;

        -- When new config data is available on the bus => load the data into internal staging registers and set the "update ready" flag.
        if isl_load = '1' then
          sl_P_pending <= islv32_freq;
          sl_H_pending <= islv32_duty_cycle;
          sl_update_ready <= '1';
        end if;
      end if;
    end process;

  counter_proc : process(isl_clk, isl_rst)
  begin
    if isl_rst = '0' then 
      sl_count_pwm <= (others => '0');
    elsif rising_edge(isl_clk) then 
      if sl_period_end = '1' then
        sl_count_pwm <= (others => '0');       -- wrap around the counter
      else
        sl_count_pwm <= std_logic_vector(unsigned(sl_count_pwm) + 1);
      end if;
    end if; 
  end process;

  sl_period_end <= '1' when sl_count_pwm = std_logic_vector(unsigned(sl_P_active) - 1) else '0';   -- counter finished one period.
  osl_output_sig <= '1' when unsigned(sl_count_pwm) < unsigned(sl_H_active) else '0';              -- output goes high depending on the duty cycle.
  
end architecture;