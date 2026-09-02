library ieee;
use ieee.std_logic_1164.all;
use IEEE.NUMERIC_STD.ALL;

-------------------------------------------------------------------------------
-- File        : cdc_arbiter.vhd
-- Project     : Two-Channel Signal Generator with CDC
-- Author      : Kiril Burlakov
-- Standard    : VHDL
-------------------------------------------------------------------------------
-- Description : Clock-domain-crossing controller. Transfers the two channels frequency and
--               duty parameters from the 33 MHz control domain to the 100 MHz generator
--               domain as one coherent set, using a four-phase request/acknowledge
--               handshake with a busy backpressure signal to the data provider. Only the
--               single-bit handshake lines are synchronized. The data bus is held stable
--               and captured under handshake control, then presented with a one-cycle load
--               pulse. Guarantees metastability-safe, coherent, no-loss / no-double-apply
--               transfer.
-------------------------------------------------------------------------------

entity cdc_arbiter is
    port (
        isl_clk100         : in std_logic;
        isl_clk33          : in std_logic;
        isl_arst100_n      : in std_logic;
        isl_arst33_n       : in std_logic;

        islv32_freq_ch0    : in std_logic_vector(31 downto 0);
        islv32_duty_ch0    : in std_logic_vector(31 downto 0);
        islv32_freq_ch1    : in std_logic_vector(31 downto 0);
        islv32_duty_ch1    : in std_logic_vector(31 downto 0);
        isl_commit33       : in std_logic;                            -- Commit input signal that comes from the 33Mhz clock domain, same as the data. Instructs the CDC Arbiter that data on the data channels is valid and need to be outputted

        oslv32_freq_ch0    : out std_logic_vector(31 downto 0);
        oslv32_duty_ch0    : out std_logic_vector(31 downto 0);
        oslv32_freq_ch1    : out std_logic_vector(31 downto 0);
        oslv32_duty_ch1    : out std_logic_vector(31 downto 0);
        osl_load           : out std_logic;                           -- Load signal that instructs the signal generator to load the new parameters and use them as the new config.
        osl_busy           : out std_logic                            -- Busy signal that tells the data provider that no data can be sent right now.
    );
end cdc_arbiter;

architecture rtl of cdc_arbiter is
    -- 33MHz domain internal signals
    type t_State is (IDLE, WAIT_ACK, WAIT_CLR);
    signal State          : t_State;
    signal slv32_freq_ch0 : std_logic_vector(31 downto 0);
    signal slv32_duty_ch0 : std_logic_vector(31 downto 0);
    signal slv32_freq_ch1 : std_logic_vector(31 downto 0);
    signal slv32_duty_ch1 : std_logic_vector(31 downto 0);
    signal sl_req33       : std_logic;
    signal sl_ack33       : std_logic;
    signal sl_busy        : std_logic;

    -- 100Mhz domain internal signals
    signal sl_req100      : std_logic;
    signal sl_req100_d    : std_logic;
    signal sl_ack100      : std_logic;
    signal sl_load        : std_logic;

    

begin
    -- 2FF syncs to allow a stable handshake between 2 clock domains
    u_req_sync : entity work.sync_2ff
    port map (isl_clk => isl_clk100, isl_rst => isl_arst100_n, isl_d => sl_req33, osl_d => sl_req100);

    u_ack_sync : entity work.sync_2ff
    port map (isl_clk => isl_clk33,  isl_rst => isl_arst33_n,  isl_d => sl_ack100, osl_d => sl_ack33);

    -- Process clocked with the slow, 33 MHz clock.
    -- Responsible for receiving the config data and initiating the handshake with the fast, 100 MHz data output.
    slow_clock : process (isl_clk33, isl_arst33_n)
    begin
        if isl_arst33_n = '0' then
            State <= IDLE;
            sl_busy <= '0';
            slv32_freq_ch0 <= (others => '0');
            slv32_duty_ch0 <= (others => '0');
            slv32_freq_ch1 <= (others => '0');
            slv32_duty_ch1 <= (others => '0');
            sl_req33 <= '0';
        elsif rising_edge(isl_clk33) then
            case State is 
                -- Waiting for commit signal from the config data provider. IDLE -> WAIT_ACK when data is received and handshake with the 100mhz domain is started.
                when IDLE => 
                    if isl_commit33 = '1' then
                        slv32_freq_ch0 <= islv32_freq_ch0;
                        slv32_duty_ch0 <= islv32_duty_ch0;
                        slv32_freq_ch1 <= islv32_freq_ch1;
                        slv32_duty_ch1 <= islv32_duty_ch1;
                        sl_req33 <= '1';
                        sl_busy <= '1';
                        State <= WAIT_ACK;
                    end if;
                -- Waiting for fast clock domain acknowledgement. WAIT_ACK -> WAIT_CLR when ack signal from fast clock domain is received.
                when WAIT_ACK =>
                    if sl_ack33 = '1' then
                        sl_req33 <= '0';
                        State <= WAIT_CLR;
                    end if;
                -- Last part of the handshake. Waiting until all handshake signals are going to 0, set busy to '0' (data sender can send new data). Go back to IDLE.
                when WAIT_CLR =>
                    if sl_ack33 = '0' then
                        sl_busy <= '0';
                        State <= IDLE;
                    end if;

            end case;
        end if;
    end process;

    -- 100Mhz process, responsible for laching the config data to the outputs and sending a load signal to the signal generator.
    fast_clock_data_latch : process (isl_clk100, isl_arst100_n)
    begin
        if isl_arst100_n = '0' then
            sl_load <= '0';
            sl_req100_d <= '0';
            oslv32_freq_ch0 <= (others => '0');
            oslv32_duty_ch0 <= (others => '0');
            oslv32_freq_ch1 <= (others => '0');
            oslv32_duty_ch1 <= (others => '0');
        elsif rising_edge(isl_clk100) then
            sl_req100_d <= sl_req100;                           -- remember last cycle's value
            sl_load <= '0'; 
            if (sl_req100 = '1') and (sl_req100_d = '0') then   -- rising edge detected -> send the data to the output, set load = '1' to instruct the generators that data on the outputs is valid and ready.
                oslv32_freq_ch0 <= slv32_freq_ch0;
                oslv32_duty_ch0 <= slv32_duty_ch0;
                oslv32_freq_ch1 <= slv32_freq_ch1;
                oslv32_duty_ch1 <= slv32_duty_ch1;
                sl_load <= '1';
            end if;
        end if;
    end process;

    -- 100 Mhz process
    -- Second part of the handshake, instructing the slow domain that data was received and sent.
    ack_back_to_slow : process (isl_clk100, isl_arst100_n)
    begin
        if isl_arst100_n = '0' then
            sl_ack100 <= '0';
        elsif rising_edge(isl_clk100) then
            if (sl_load = '1') then
               sl_ack100 <= '1';
            elsif sl_req100 = '0' then
                sl_ack100 <= '0';
            end if;
        end if;
    end process;

    osl_load <= sl_load;
    osl_busy <= sl_busy;
end architecture;