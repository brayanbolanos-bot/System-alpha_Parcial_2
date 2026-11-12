-- TCS3200 autonomo: mide R, G y B y manda la senal a los 3 LEDs (activo alto: 1 = prendido).
-- Se prende unicamente el LED del canal con mas cuentas (ganador unico).
-- Escala de salida 100 %. Un solo archivo, sin otros componentes.
-- NUEVO: el resultado (que LEDs prender) debe repetirse N_CONFIRM veces seguidas
--        antes de pasar a los LEDs; mientras tanto se mantiene el ultimo confirmado.
library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.numeric_std.ALL;

entity TCS_Solo is
    port (
        CLK : in std_logic;
        RST : in std_logic;               -- activo en '0'

        TCS_OUT : in  std_logic;
        TCS_S0, TCS_S1, TCS_S2, TCS_S3, TCS_OE : out std_logic;

        LED_ROJO, LED_AZUL, LED_VERDE : out std_logic
    );
end TCS_Solo;

architecture arch of TCS_Solo is
    constant SETTLE_CYC : natural := 250000;   -- 5 ms
    constant WINDOW_CYC : natural := 500000;   -- 10 ms
    constant MIN_COUNT  : natural := 32;
    constant SIM_PCT    : natural := 85;       -- si el 2do canal >= 85 % del mayor -> indefinido (blanco/gris), todo apagado
    constant G_PCT      : natural := 125;      -- NUEVO: ganancia del canal verde en % (125 = verde x1.25). Rojo y azul van al 100 %
    constant N_CONFIRM  : natural := 4;        -- NUEVO: lecturas iguales seguidas (4 x 45 ms = ~180 ms)

    type st_t is (S_SETTLE, S_COUNT, S_NEXT, S_SHOW);
    signal st : st_t;
    signal idx  : integer range 0 to 2;
    signal tmr  : integer range 0 to 1048575;
    signal pcnt, cR, cG, cB : unsigned(15 downto 0);
    signal o0, o1, o2 : std_logic;
    signal rise : std_logic;
    signal onR, onG, onB : std_logic;
    signal cand : std_logic_vector(2 downto 0);   -- NUEVO: ultimo resultado (R,G,B) candidato
    signal hits : integer range 0 to N_CONFIRM;   -- NUEVO: veces seguidas que se repitio cand
begin
    TCS_S0 <= '1';          -- escala 100 %
    TCS_S1 <= '1';
    TCS_OE <= '0';

    TCS_S2 <= '1' when idx = 1 else '0';   -- R: 00, G: 11, B: 01
    TCS_S3 <= '0' when idx = 0 else '1';

    rise <= o1 and (not o2);

    -- CAMBIO: LEDs activo ALTO ('1' = prendido)
    LED_ROJO  <= onR;
    LED_VERDE <= onG;
    LED_AZUL  <= onB;

    process (CLK, RST)
        variable wR, wG, wB : natural;               -- NUEVO: canales ya compensados (x100, verde x G_PCT)
        variable m : natural;                        -- canal mayor (compensado)
        variable s : natural;                        -- segundo canal mas alto (compensado)
        variable v : std_logic_vector(2 downto 0);   -- resultado de esta lectura (R,G,B)
    begin
        if RST = '0' then
            st <= S_SETTLE; idx <= 0; tmr <= 0; pcnt <= (others => '0');
            cR <= (others => '0'); cG <= (others => '0'); cB <= (others => '0');
            o0 <= '0'; o1 <= '0'; o2 <= '0';
            onR <= '0'; onG <= '0'; onB <= '0';
            cand <= "000"; hits <= 0;                 -- NUEVO
        elsif rising_edge(CLK) then
            o0 <= TCS_OUT; o1 <= o0; o2 <= o1;

            case st is
                when S_SETTLE =>
                    if tmr = SETTLE_CYC - 1 then
                        tmr <= 0; pcnt <= (others => '0'); st <= S_COUNT;
                    else
                        tmr <= tmr + 1;
                    end if;

                when S_COUNT =>
                    if rise = '1' and pcnt /= 65535 then
                        pcnt <= pcnt + 1;
                    end if;
                    if tmr = WINDOW_CYC - 1 then
                        tmr <= 0;
                        if idx = 0 then cR <= pcnt;
                        elsif idx = 1 then cG <= pcnt;
                        else cB <= pcnt;
                        end if;
                        st <= S_NEXT;
                    else
                        tmr <= tmr + 1;
                    end if;

                when S_NEXT =>
                    if idx = 2 then
                        st <= S_SHOW;
                    else
                        idx <= idx + 1; tmr <= 0; st <= S_SETTLE;
                    end if;

                when S_SHOW =>
                    -- NUEVO: compensacion por canal. Todo se escala x100 para no usar
                    -- division; el verde se multiplica por G_PCT (125 = +25 %) porque el
                    -- TCS3200 responde menos en ese canal.
                    wR := to_integer(cR) * 100;
                    wG := to_integer(cG) * G_PCT;
                    wB := to_integer(cB) * 100;

                    -- Ganador unico: se prende solo el LED del canal (compensado) mayor.
                    -- m = canal mayor, s = segundo canal mas alto.
                    v := "000";
                    if wR >= wG and wR >= wB then
                        m := wR; v(2) := '1';                      -- rojo
                        if wG > wB then s := wG; else s := wB; end if;
                    elsif wG >= wB then
                        m := wG; v(1) := '1';                      -- verde
                        if wR > wB then s := wR; else s := wB; end if;
                    else
                        m := wB; v(0) := '1';                      -- azul
                        if wR > wG then s := wR; else s := wG; end if;
                    end if;

                    -- Color indefinido -> todo apagado.
                    --  * muy poca luz (m < MIN_COUNT, en la misma escala x100), o
                    --  * el segundo canal esta a >= SIM_PCT % del ganador (blanco, gris,
                    --    luz ambiente: los canales salen parecidos y no hay color dominante)
                    if m < MIN_COUNT * 100 or
                       s * 100 >= m * SIM_PCT then
                        v := "000";
                    end if;

                    -- NUEVO: confirmacion. Solo cuando el mismo resultado se repite
                    -- N_CONFIRM veces seguidas se pasa a los LEDs.
                    if v = cand then
                        if hits < N_CONFIRM then
                            hits <= hits + 1;
                        end if;
                        if hits >= N_CONFIRM - 1 then
                            onR <= cand(2);
                            onG <= cand(1);
                            onB <= cand(0);
                        end if;
                    else
                        cand <= v;
                        hits <= 1;
                    end if;

                    idx <= 0; tmr <= 0; st <= S_SETTLE;
            end case;
        end if;
    end process;
end arch;