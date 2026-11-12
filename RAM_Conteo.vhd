-- RAM 16x8, 1 puerto de escritura/lectura (A) + 1 de lectura (B, para displays)
-- Mapa: ver FSM_Control.vhd (0=total, 1..6=color x tamano, 7=NI, 8=ultimo color, 9=ultimo tamano)
library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.numeric_std.ALL;

entity RAM_Conteo is
    port (
        Clk    : in  std_logic;
        We     : in  std_logic;
        Addr_A : in  std_logic_vector(3 downto 0);
        Din    : in  std_logic_vector(7 downto 0);
        Dout_A : out std_logic_vector(7 downto 0);
        Addr_B : in  std_logic_vector(3 downto 0);
        Dout_B : out std_logic_vector(7 downto 0)
    );
end RAM_Conteo;

architecture arch of RAM_Conteo is
    type ram_t is array (0 to 15) of std_logic_vector(7 downto 0);
    signal mem : ram_t := (others => (others => '0'));
begin
    process (Clk)
    begin
        if rising_edge(Clk) then
            if We = '1' then
                mem(to_integer(unsigned(Addr_A))) <= Din;
            end if;
        end if;
    end process;

    Dout_A <= mem(to_integer(unsigned(Addr_A)));
    Dout_B <= mem(to_integer(unsigned(Addr_B)));
end arch;