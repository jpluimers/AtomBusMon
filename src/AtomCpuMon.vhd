--------------------------------------------------------------------------------
-- Copyright (c) 2015 David Banks
--
--------------------------------------------------------------------------------
--   ____  ____
--  /   /\/   /
-- /___/  \  /
-- \   \   \/
--  \   \
--  /   /         Filename  : AtomBusMon.vhd
-- /___/   /\     Timestamp : 30/05/2015
-- \   \  /  \
--  \___\/\___\
--
--Design Name: AtomBusMon
--Device: XC3S250E

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use work.OhoPack.all ;


entity AtomCpuMon is
    generic (
       UseT65Core     : boolean := true;
       UseAlanDCore   : boolean := false;
       LEDsActiveHigh : boolean := false;    -- default value correct for GODIL
       SW1ActiveHigh  : boolean := true;     -- default value correct for GODIL
       SW2ActiveHigh  : boolean := false;    -- default value correct for GODIL
       ClkMult        : integer := 10;       -- default value correct for GODIL
       ClkDiv         : integer := 31;       -- default value correct for GODIL
       ClkPer         : real    := 20.345    -- default value correct for GODIL
       );
    port (
        clock49         : in    std_logic;

        -- 6502 Signals
        Phi0            : in    std_logic;
        Phi1            : out   std_logic;
        Phi2            : out   std_logic;
        IRQ_n           : in    std_logic;
        NMI_n           : in    std_logic;
        Sync            : out   std_logic;
        Addr            : out   std_logic_vector(15 downto 0);
        R_W_n           : out   std_logic;
        Data            : inout std_logic_vector(7 downto 0);
        SO_n            : in    std_logic;
        Res_n           : inout std_logic;
        Rdy             : in    std_logic;

        -- External trigger inputs
        trig             : in    std_logic_vector(1 downto 0);

        -- Jumpers
        fakeTube_n      : in     std_logic;

        -- Serial Console
        avr_RxD         : in     std_logic;
        avr_TxD         : out    std_logic;

        -- GODIL Switches
        sw1              : in    std_logic;
        sw2              : in    std_logic;

        -- GODIL LEDs
        led3             : out   std_logic;
        led6             : out   std_logic;
        led8             : out   std_logic;

        -- OHO_DY1 connected to test connector
        tmosi            : out   std_logic;
        tdin             : out   std_logic;
        tcclk            : out   std_logic
    );
end AtomCpuMon;

architecture behavioral of AtomCpuMon is

    signal clock_avr     : std_logic;

    signal Din           : std_logic_vector(7 downto 0);
    signal Dout          : std_logic_vector(7 downto 0);

    signal IRQ_n_sync    : std_logic;
    signal NMI_n_sync    : std_logic;

    signal Addr_int      : std_logic_vector(15 downto 0);
    signal R_W_n_int     : std_logic;

    signal Phi0_a        : std_logic;
    signal Phi0_b        : std_logic;
    signal Phi0_c        : std_logic;
    signal Phi0_d        : std_logic;
    signal cpu_clk       : std_logic;
    signal busmon_clk    : std_logic;

    signal Res_n_in      : std_logic;
    signal Res_n_out     : std_logic;

    signal led3_n         : std_logic;  -- led to indicate ext trig 0 is active
    signal led6_n         : std_logic;  -- led to indicate ext trig 1 is active
    signal led8_n         : std_logic;  -- led to indicate CPU has hit a breakpoint (and is stopped)
    signal sw_interrupt_n : std_logic;  -- switch to pause the CPU
    signal sw_reset_n     : std_logic;  -- switch to reset the CPU

begin

    -- Generics allows polarity of switches/LEDs to be tweaked from the project file
    sw_interrupt_n <= not sw1 when SW1ActiveHigh else sw1;
    sw_reset_n     <= not sw2 when SW2ActiveHigh else sw2;
    led3           <= not led3_n when LEDsActiveHigh else led3_n;
    led6           <= not led6_n when LEDsActiveHigh else led6_n;
    led8           <= not led8_n when LEDsActiveHigh else led8_n;

    inst_dcm0 : entity work.DCM0
      generic map (
        ClkMult      => ClkMult,
        ClkDiv       => ClkDiv,
        ClkPer       => ClkPer
      )
      port map(
        CLKIN_IN     => clock49,
        CLKFX_OUT    => clock_avr
      );

    core : entity work.MOS6502CpuMonCore
    generic map (
       UseT65Core        => UseT65Core,
       UseAlanDCore      => UseAlanDCore,
       avr_prog_mem_size => 1024 * 8
    )
    port map (
        clock_avr    => clock_avr,
        busmon_clk   => busmon_clk,
        busmon_clken => '1',
        cpu_clk      => cpu_clk,
        cpu_clken    => '1',
        IRQ_n        => IRQ_n_sync,
        NMI_n        => NMI_n_sync,
        Sync         => Sync,
        Addr         => Addr_int,
        R_W_n        => R_W_n_int,
        Din          => Din,
        Dout         => Dout,
        SO_n         => SO_n,
        Res_n_in     => Res_n_in,
        Res_n_out    => Res_n_out,
        Rdy          => Rdy,
        trig         => trig,
        avr_RxD      => avr_RxD,
        avr_TxD      => avr_TxD,
        sw1          => not sw_interrupt_n,
        nsw2         => sw_reset_n,
        led3         => led3_n,
        led6         => led6_n,
        led8         => led8_n,
        tmosi        => tmosi,
        tdin         => tdin,
        tcclk        => tcclk
    );

    -- Tristate buffer driving reset back out
    Res_n_in <= Res_n;
    Res_n <= '0' when Res_n_out <= '0' else 'Z';

    sync_gen : process(cpu_clk)
    begin
        if rising_edge(cpu_clk) then
          NMI_n_sync <= NMI_n;
          IRQ_n_sync <= IRQ_n;
        end if;
    end process;

    data_latch : process(Phi0_b)
    begin
        if falling_edge(Phi0_b) then
            if (fakeTube_n = '0' and Addr_int = x"FEE0") then
                Din        <= x"FE";
            else
                Din        <= Data;
            end if;
        end if;
    end process;

    Data  <= Dout when Phi0_c = '1' and R_W_n_int = '0' else (others => 'Z');
    R_W_n <= R_W_n_int;
    Addr  <= Addr_int;

    clk_gen : process(clock49)
    begin
        if rising_edge(clock49) then
          Phi0_a <= Phi0;
          Phi0_b <= Phi0_a;
          Phi0_c <= Phi0_b;
          Phi0_d <= Phi0_c;
        end if;
    end process;

    Phi1       <= not (Phi0_b or Phi0_d);
    Phi2       <= Phi0_b and Phi0_d;
    cpu_clk    <= not Phi0_d;
    busmon_clk <= Phi0_d;

end behavioral;
