-- Ciberseguridad: contrasena por botones para habilitar el sistema.
-- Un solo archivo, sin otros componentes (el antirrebote va adentro).
--
-- Clave:  BOTON 0 -> BOTON 0 -> BOTON 1 -> BOTON 2
--
--   Step 0 --(b0)--> Step 1 --(b0)--> Step 2 --(b1)--> Step 3 --(b2)--> UNLOCKED = '1'
--     ^                 |                |                |
--     +---- boton malo (o 2 botones a la vez) en cualquier paso ----+
--                       |
--                       v
--                    ALARMA: Buzzer suena ALARM_CYC ciclos (1 s) y se reinicia la clave
--
-- * Al prenderse la FPGA queda bloqueado (Unlocked = '0').
-- * Con la clave correcta Unlocked = '1' y se queda asi hasta que se APAGUE la FPGA
--   (el boton de reset NO lo vuelve a bloquear, salvo que pongas RST_RELOCK => true).
-- * Mientras suena la alarma se ignoran los botones.
-- * Buzzer: onda cuadrada de 2 kHz mientras dura la alarma (sirve para buzzer pasivo;
--   en uno activo tambien suena). Cambia TONE_HALF para otro tono.
library IEEE;
use IEEE.std_logic_1164.ALL;

entity Ciberseguridad is
    generic (
        ACTIVE_LOW : boolean := true;      -- true: boton presionado = '0' (asi son los de la DE0)
        DEB_CYC    : natural := 500000;    -- antirrebote 10 ms @ 50 MHz
        ALARM_CYC  : natural := 50000000;  -- duracion de la alarma: 1 s
        TONE_HALF  : natural := 12500;     -- medio periodo del tono: 2 kHz
        RST_RELOCK : boolean := false      -- true: Rst = '0' tambien vuelve a bloquear
    );
    port (
        Clk      : in  std_logic;                       -- 50 MHz
        Rst      : in  std_logic;                       -- activo en '0'
        Btn      : in  std_logic_vector(2 downto 0);    -- botones 0, 1, 2
        Unlocked : out std_logic;                       -- '1' = sistema habilitado
        Buzzer   : out std_logic;                       -- al modulo buzzer
        Led_Ok   : out std_logic;                       -- LED: prende al poner bien la clave (queda prendido)
        Led_Err  : out std_logic;                       -- LED: prende mientras dura la alarma (clave mala)
        Step     : out std_logic_vector(1 downto 0)     -- progreso de la clave (0..3), para LEDs de prueba
    );
end Ciberseguridad;

architecture arch of Ciberseguridad is

    type seq_t is array (0 to 3) of std_logic_vector(2 downto 0);
    constant SEQ : seq_t := ("001", "001", "010", "100");   -- b0, b0, b1, b2

    signal lvl, rise : std_logic_vector(2 downto 0) := (others => '0');

    signal unl       : std_logic := '0';   -- sin reset: solo el apagado lo borra
    signal ok_pulse  : std_logic;
    signal stp       : integer range 0 to 3;
    signal alarm     : std_logic;
    signal alarm_cnt : natural range 0 to ALARM_CYC;
    signal tone_cnt  : natural range 0 to TONE_HALF;
    signal tone      : std_logic;

begin

    ----------------------------------------------------------------
    -- Sincronizador + antirrebote + pulso de flanco, uno por boton
    ----------------------------------------------------------------
    GEN_BTN : for i in 0 to 2 generate
        signal s1, s2, raw : std_logic := '0';
        signal l           : std_logic := '0';
        signal c           : natural range 0 to DEB_CYC := 0;
    begin
        raw <= (not s2) when ACTIVE_LOW else s2;

        process (Clk, Rst)
        begin
            if Rst = '0' then
                s1 <= '0'; s2 <= '0'; l <= '0'; c <= 0;
                rise(i) <= '0';
                if ACTIVE_LOW then s1 <= '1'; s2 <= '1'; end if;
            elsif rising_edge(Clk) then
                s1 <= Btn(i);
                s2 <= s1;
                rise(i) <= '0';
                if raw = l then
                    c <= 0;
                elsif c = DEB_CYC - 1 then
                    l       <= raw;
                    rise(i) <= raw;      -- pulso solo al PRESIONAR
                    c       <= 0;
                else
                    c <= c + 1;
                end if;
            end if;
        end process;

        lvl(i) <= l;
    end generate;

    ----------------------------------------------------------------
    -- FSM de la clave + alarma
    ----------------------------------------------------------------
    ok_pulse <= '1' when (stp = 3 and rise = SEQ(3) and alarm = '0' and unl = '0') else '0';

    process (Clk, Rst)
    begin
        if Rst = '0' then
            stp       <= 0;
            alarm     <= '0';
            alarm_cnt <= 0;
        elsif rising_edge(Clk) then
            if alarm = '1' then
                -- suena la alarma, botones ignorados
                if alarm_cnt = ALARM_CYC - 1 then
                    alarm     <= '0';
                    alarm_cnt <= 0;
                    stp       <= 0;
                else
                    alarm_cnt <= alarm_cnt + 1;
                end if;

            elsif unl = '0' and rise /= "000" then
                if rise = SEQ(stp) then          -- boton correcto (y solo ese)
                    if stp = 3 then
                        stp <= 0;                -- clave completa (unl se prende abajo)
                    else
                        stp <= stp + 1;
                    end if;
                else                             -- boton equivocado o 2 a la vez
                    alarm     <= '1';
                    alarm_cnt <= 0;
                end if;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- Bandera de desbloqueo (sin reset: nace en '0' al prender la FPGA)
    ----------------------------------------------------------------
    process (Clk)
    begin
        if rising_edge(Clk) then
            if RST_RELOCK and Rst = '0' then
                unl <= '0';
            elsif ok_pulse = '1' then
                unl <= '1';
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- Tono del buzzer
    ----------------------------------------------------------------
    process (Clk)
    begin
        if rising_edge(Clk) then
            if alarm = '0' then
                tone_cnt <= 0;
                tone     <= '0';
            elsif tone_cnt = TONE_HALF - 1 then
                tone_cnt <= 0;
                tone     <= not tone;
            else
                tone_cnt <= tone_cnt + 1;
            end if;
        end if;
    end process;

    Buzzer   <= tone when alarm = '1' else '0';
    Unlocked <= unl;
    Led_Ok   <= unl;
    Led_Err  <= alarm;
    Step     <= "00" when stp = 0 else
                "01" when stp = 1 else
                "10" when stp = 2 else
                "11";

end arch;
