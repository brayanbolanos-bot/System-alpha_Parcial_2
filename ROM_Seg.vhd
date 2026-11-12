-- ROM 16x7: tabla de 7 segmentos 0-9 y A-F (reemplaza decoder7segwithse)
library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.numeric_std.ALL;

entity ROM_Seg is
    generic ( COMMON_ANODE : boolean := true );  -- false si tus displays son catodo comun
    port (
        Addr : in  std_logic_vector(3 downto 0);
        Data : out std_logic_vector(6 downto 0)  -- orden: gfedcba
    );
end ROM_Seg;

architecture arch of ROM_Seg is
    type rom_t is array (0 to 15) of std_logic_vector(6 downto 0);
    constant ROM : rom_t := (
        "1000000", "1111001", "0100100", "0110000",   -- 0 1 2 3
        "0011001", "0010010", "0000010", "1111000",   -- 4 5 6 7
        "0000000", "0010000", "0001000", "0000011",   -- 8 9 A b
        "1000110", "0100001", "0000110", "0001110");  -- C d E F
begin
    Data <= ROM(to_integer(unsigned(Addr))) when COMMON_ANODE
            else not ROM(to_integer(unsigned(Addr)));
end arch;