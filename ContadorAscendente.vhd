library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.numeric_std.all;

entity ContadorAscendente is
    port (
        Clock, reset : in  std_logic;
        EN           : in  std_logic;
        CNT          : out std_logic_vector(3 downto 0)
    );
end ContadorAscendente;

architecture arch_ContadorAscendente of ContadorAscendente is
    signal CNT_int : integer range 0 to 9 := 0;
begin
    process (Clock, reset)
    begin
        if reset = '0' then
            CNT_int <= 0;
        elsif rising_edge(Clock) then
            if EN = '1' then
                if CNT_int = 9 then
                    CNT_int <= 0;
                else
                    CNT_int <= CNT_int + 1;
                end if;
            end if;
        end if;
    end process;

    CNT <= std_logic_vector(to_unsigned(CNT_int, 4));
end arch_ContadorAscendente;