-- Puente_H: control del motor de la banda a traves de un L298N (canal A).
-- Pensado para probarse SOLO en la placa (entidad superior) o dentro de SystemAlfa.
--
--   Rst      : activo en '0'. Con Rst = '0' NO hace nada: ENA, IN1 e IN2 quedan a 0
--              aunque se muevan los demas switches.
--   FREQ_ON  : enable. Solo tiene efecto con Rst = '1'. Con FREQ_ON = 0 el motor se para.
--   FREQ_SEL : los mismos switches de seleccion de velocidad del sistema:
--                 00 -> velocidad 2, normal     (60 %)
--                 01 -> velocidad 3, muy rapida (100 %)
--                 10 -> velocidad 1, lenta      (35 %)
--                 11 -> velocidad 0, muy lenta  (20 %)
--   ENA      : PWM de 200 Hz -> pin ENA del L298N (QUITAR EL JUMPER DE ENA, si no
--              el motor va siempre a tope y no se notan las velocidades)
--   Los porcentajes estan muy separados para que se distingan a simple vista; se
--   cambian en los generics sin tocar la logica.
--   IN1, IN2 : sentido de giro -> pines IN1 e IN2 del L298N (sentido fijo: IN1 = 1, IN2 = 0)
library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.numeric_std.ALL;

entity Puente_H is
    generic (
        PERIOD_CYC : natural := 250000;    -- 200 Hz @ 50 MHz (pulsos largos: arranca mejor en lento)
        DUTY_V0    : natural := 20;        -- % muy lenta  (FREQ_SEL = 11)
        DUTY_V1    : natural := 35;        -- % lenta      (FREQ_SEL = 10)
        DUTY_V2    : natural := 60;        -- % normal     (FREQ_SEL = 00)
        DUTY_V3    : natural := 100        -- % muy rapida (FREQ_SEL = 01)
    );
    port (
        Clk      : in  std_logic;                      -- 50 MHz
        Rst      : in  std_logic;                      -- activo en '0'
        FREQ_ON  : in  std_logic;                      -- enable
        FREQ_SEL : in  std_logic_vector(2 downto 1);   -- seleccion de velocidad
        ENA      : out std_logic;                      -- PWM -> ENA del L298N
        IN1      : out std_logic;                      -- -> IN1 del L298N
        IN2      : out std_logic                       -- -> IN2 del L298N
    );
end Puente_H;

architecture arch of Puente_H is
    signal cnt    : natural range 0 to PERIOD_CYC - 1;
    signal limite : natural range 0 to PERIOD_CYC;
    signal ena_r, in1_r, in2_r : std_logic;
begin

    -- ciclos en alto del PWM segun los switches de velocidad
    limite <= (PERIOD_CYC / 100) * DUTY_V2 when FREQ_SEL = "00" else   -- normal
              (PERIOD_CYC / 100) * DUTY_V3 when FREQ_SEL = "01" else   -- muy rapida
              (PERIOD_CYC / 100) * DUTY_V1 when FREQ_SEL = "10" else   -- lenta
              (PERIOD_CYC / 100) * DUTY_V0;                            -- muy lenta

    process (Clk, Rst)
    begin
        if Rst = '0' then                    -- reset abajo: todo a 0, no hace nada
            cnt   <= 0;
            ena_r <= '0';
            in1_r <= '0';
            in2_r <= '0';
        elsif rising_edge(Clk) then
            -- contador del periodo del PWM
            if cnt = PERIOD_CYC - 1 then
                cnt <= 0;
            else
                cnt <= cnt + 1;
            end if;

            -- salidas: solo con el enable activo
            if FREQ_ON = '1' then
                in1_r <= '1';
                in2_r <= '0';
                if cnt < limite then
                    ena_r <= '1';
                else
                    ena_r <= '0';
                end if;
            else
                in1_r <= '0';
                in2_r <= '0';
                ena_r <= '0';
            end if;
        end if;
    end process;

    ENA <= ena_r;
    IN1 <= in1_r;
    IN2 <= in2_r;

end arch;
