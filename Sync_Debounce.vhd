	-- Sincroniza + antirrebote + pulso de flanco para entradas externas (IR, etc.)
library IEEE;
use IEEE.std_logic_1164.ALL;

entity Sync_Debounce is
    generic (
        ACTIVE_LOW : boolean := true;     -- true: el sensor da '0' al detectar
        DEB_CYC    : natural := 500000    -- 10 ms @ 50 MHz
    );
    port (
        Clk, Rst : in  std_logic;         -- Rst activo en '0'
        Din      : in  std_logic;
        Level    : out std_logic;         -- '1' = detectado (ya filtrado)
        Rise     : out std_logic          -- pulso de 1 ciclo al empezar a detectar
    );
end Sync_Debounce;

architecture arch of Sync_Debounce is
    function idle_val(a : boolean) return std_logic is
    begin
        if a then return '1'; else return '0'; end if;
    end function;

    signal s1, s2, raw, lvl : std_logic;
    signal cnt : natural range 0 to DEB_CYC := 0;
begin
    raw <= (not s2) when ACTIVE_LOW else s2;

    process (Clk, Rst)
    begin
        if Rst = '0' then
            s1 <= idle_val(ACTIVE_LOW);
            s2 <= idle_val(ACTIVE_LOW);
            lvl <= '0';
            cnt <= 0;
            Rise <= '0';
        elsif rising_edge(Clk) then
            s1 <= Din;
            s2 <= s1;
            Rise <= '0';
            if raw = lvl then
                cnt <= 0;
            elsif cnt = DEB_CYC - 1 then
                lvl  <= raw;
                Rise <= raw;
                cnt  <= 0;
            else
                cnt <= cnt + 1;
            end if;
        end if;
    end process;

    Level <= lvl;
end arch;