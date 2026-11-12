-- Servo_180: prueba de UN servo. Al subir el switch, el servo barre 0 -> 180 grados,
-- se queda un momento arriba y vuelve solo a 0 grados.
--
--   SW sube ──► IDLE ──► GO (0->180) ──► HOLD (pausa) ──► BACK (180->0) ──► WAIT ──► IDLE
--                 ▲                                                          │
--                 └────────── baja el switch para poder repetir ◄────────────┘
--
-- * Solo hace UN ciclo por cada subida del switch. Para repetirlo hay que bajarlo y subirlo otra vez.
-- * El movimiento es gradual (barrido): el ancho del pulso cambia STEP_CYC en cada periodo de 20 ms.
-- * Pulso de 0.5 ms (~0 grados) a 2.5 ms (~180 grados), tipico de un SG90 / MG90.
--   Si tu servo solo tiene 1.0 - 2.0 ms de recorrido, o si al llegar a un extremo
--   "zumba" o vibra, acorta MIN_CYC / MAX_CYC (ej. 50000 y 100000).
--
--   0.5 ms = 25000 | 1.0 ms = 50000 | 1.5 ms = 75000 | 2.0 ms = 100000 | 2.5 ms = 125000  (@ 50 MHz)
library IEEE;
use IEEE.std_logic_1164.ALL;

entity Servo_180 is
    generic (
        PERIOD_CYC  : natural := 1000000;   -- 20 ms @ 50 MHz
        MIN_CYC     : natural := 25000;     -- 0.5 ms -> posicion original (0 grados)
        MAX_CYC     : natural := 125000;    -- 2.5 ms -> 180 grados
        STEP_CYC    : natural := 2500;      -- cuanto cambia el ancho por periodo (40 pasos = 0.8 s por barrido)
        HOLD_PERIODS: natural := 25         -- pausa arriba: 25 x 20 ms = 0.5 s
    );
    port (
        Clk       : in  std_logic;          -- 50 MHz
        Rst       : in  std_logic;          -- activo en '0'
        Sw        : in  std_logic;          -- '1' = switch arriba -> dispara el movimiento
        Servo_Pwm : out std_logic           -- al pin de senal del servo
    );
end Servo_180;

architecture arch of Servo_180 is
    type st_t is (S_IDLE, S_GO, S_HOLD, S_BACK, S_WAIT);
    signal st       : st_t;
    signal cnt      : natural range 0 to PERIOD_CYC - 1;
    signal width    : natural range 0 to PERIOD_CYC;
    signal hold_cnt : natural range 0 to HOLD_PERIODS;
    signal s1, s2   : std_logic;            -- sincronizador del switch
begin

    process (Clk, Rst)
    begin
        if Rst = '0' then
            st        <= S_IDLE;
            cnt       <= 0;
            width     <= MIN_CYC;
            hold_cnt  <= 0;
            s1        <= '0';
            s2        <= '0';
            Servo_Pwm <= '0';
        elsif rising_edge(Clk) then
            s1 <= Sw;
            s2 <= s1;

            if cnt = PERIOD_CYC - 1 then
                cnt <= 0;

                -- la maquina avanza UNA vez por periodo (cada 20 ms)
                case st is
                    when S_IDLE =>
                        width <= MIN_CYC;
                        if s2 = '1' then
                            st <= S_GO;
                        end if;

                    when S_GO =>                       -- 0 -> 180
                        if width + STEP_CYC >= MAX_CYC then
                            width    <= MAX_CYC;
                            hold_cnt <= 0;
                            st       <= S_HOLD;
                        else
                            width <= width + STEP_CYC;
                        end if;

                    when S_HOLD =>                     -- pausa arriba
                        if hold_cnt = HOLD_PERIODS - 1 then
                            st <= S_BACK;
                        else
                            hold_cnt <= hold_cnt + 1;
                        end if;

                    when S_BACK =>                     -- 180 -> 0
                        if width <= MIN_CYC + STEP_CYC then
                            width <= MIN_CYC;
                            st    <= S_WAIT;
                        else
                            width <= width - STEP_CYC;
                        end if;

                    when S_WAIT =>                     -- espera a que bajes el switch
                        if s2 = '0' then
                            st <= S_IDLE;
                        end if;
                end case;
            else
                cnt <= cnt + 1;
            end if;

            -- PWM
            if cnt < width then
                Servo_Pwm <= '1';
            else
                Servo_Pwm <= '0';
            end if;
        end if;
    end process;

end arch;