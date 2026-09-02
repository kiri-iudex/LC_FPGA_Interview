library ieee;
use ieee.std_logic_1164.all;
use IEEE.NUMERIC_STD.ALL;

entity two_ch_sig_generator is
    port(
        isl_clk100 : in std_logic;
        isl_clk33 : in std_logic;

        isl_arst_n : in std_logic;

        isl_commit : in std_logic;

        islv32_duty_ch0 : in std_logic_vector(31 downto 0);
        islv32_freq_ch0 : in std_logic_vector(31 downto 0);
        islv32_duty_ch1 : in std_logic_vector(31 downto 0);
        islv32_freq_ch1 : in std_logic_vector(31 downto 0);

        osl_busy : out std_logic;
        osl_sig_ch0 : out std_logic;
        osl_sig_ch1 : out std_logic
    );
end entity;

architecture rtl of two_ch_sig_generator is
    signal sl_rst33_n : std_logic := '0';
    signal sl_rst100_n : std_logic := '0';

    signal sl_load : std_logic := '0';

    signal slv32_duty_ch0 : std_logic_vector(31 downto 0) := (others => '0');
    signal slv32_duty_ch1 : std_logic_vector(31 downto 0) := (others => '0');
    signal slv32_freq_ch0 : std_logic_vector(31 downto 0) := (others => '0');
    signal slv32_freq_ch1 : std_logic_vector(31 downto 0) := (others => '0');
begin
    RST_SYNC_33 : entity work.reset_sync(rtl)
    port map(
        isl_clk => isl_clk33,
        isl_async_rst_n => isl_arst_n,
        osl_rst_n => sl_rst33_n
    );

    RST_SYNC_100 : entity work.reset_sync(rtl)
    port map(
        isl_clk => isl_clk100,
        isl_async_rst_n => isl_arst_n,
        osl_rst_n => sl_rst100_n
    );

    CDC_ARBITER : entity work.cdc_arbiter(rtl)
    port map(
        isl_clk100 => isl_clk100,
        isl_clk33 => isl_clk33,

        isl_arst100_n => sl_rst100_n,
        isl_arst33_n => sl_rst33_n,

        islv32_freq_ch0 => islv32_freq_ch0,
        islv32_duty_ch0 => islv32_duty_ch0,
        islv32_freq_ch1 => islv32_freq_ch1,
        islv32_duty_ch1 => islv32_duty_ch1,
        isl_commit33 => isl_commit,

        oslv32_freq_ch0 => slv32_freq_ch0,
        oslv32_duty_ch0 => slv32_duty_ch0,
        oslv32_freq_ch1 => slv32_freq_ch1,
        oslv32_duty_ch1 => slv32_duty_ch1,
        osl_load => sl_load,
        osl_busy => osl_busy
    );

    SIG_GEN_CH0 : entity work.sig_generator(rtl)
    port map(
        isl_clk => isl_clk100,
        isl_rst => sl_rst100_n,
        islv32_duty_cycle => slv32_duty_ch0,
        islv32_freq => slv32_freq_ch0,
        isl_load => sl_load,
        osl_output_sig => osl_sig_ch0
    );

    SIG_GEN_CH1 : entity work.sig_generator(rtl)
    port map(
        isl_clk => isl_clk100,
        isl_rst => sl_rst100_n,
        islv32_duty_cycle => slv32_duty_ch1,
        islv32_freq => slv32_freq_ch1,
        isl_load => sl_load,
        osl_output_sig => osl_sig_ch1
    );

end architecture;