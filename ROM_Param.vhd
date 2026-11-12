-- ROM 4x16: parametros de calibracion del color (cambialos SIN tocar la logica)
library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.numeric_std.ALL;

entity ROM_Param is
    port (
        Addr : in  std_logic_vector(1 downto 0);
        Data : out std_logic_vector(15 downto 0)
    );
end ROM_Param;

architecture arch of ROM_Param is
    type rom_t is array (0 to 3) of std_logic_vector(15 downto 0);
    constant ROM : rom_t := (
        x"0100",  -- 0: conteo minimo del canal ganador (si es menor -> NI)
        x"0040",  -- 1: margen minimo entre ganador y segundo (si es menor -> NI)
        x"0000",  -- 2: libre
        x"0000"   -- 3: libre
    );
begin
    Data <= ROM(to_integer(unsigned(Addr)));
end arch;