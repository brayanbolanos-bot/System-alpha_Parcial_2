library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.numeric_std.ALL;

entity SystemAlfa is
    port (
        CLK : in std_logic;                 -- reloj de 50 MHz
        RST : in std_logic;                 -- activo en '0'

        FREQ_SEL : in std_logic_vector(2 downto 1);
        FREQ_ON  : in std_logic;
        MODE     : in std_logic;            -- 0: conteo / 1: monitoreo
        SEL_VIEW : in std_logic_vector(2 downto 0);  -- MODE 0: bit2 = tamano (0 pequena, 1 grande)

        TCS_OUT : in  std_logic;
        TCS_S0, TCS_S1, TCS_S2, TCS_S3, TCS_OE : out std_logic;

        IR_PRES : in std_logic;
        IR_SIZE : in std_logic;

        MOTOR_PWM, MOTOR_IN1, MOTOR_IN2 : out std_logic;   -- puente H (L298N): ENA, IN1, IN2
        SERVO1_PWM : out std_logic;                        -- servo 1: tamano = 0 (pequenas)
        SERVO2_PWM : out std_logic;                        -- servo 2: tamano = 1 (grandes)

        DIS1, DIS2, DIS3, DIS4 : out std_logic_vector(6 downto 0);
        FRECUENCIA  : out std_logic;
        Led_CLK     : out std_logic;
        LED_OBJETO  : out std_logic;
        LED_ESTADO  : out std_logic_vector(3 downto 0);
        LED_ROJO, LED_AZUL, LED_VERDE : out std_logic;

        -- Ciberseguridad (clave por botones: B0 -> B0 -> B1 -> B2)
        BTN      : in  std_logic_vector(2 downto 0);   -- botones 0, 1, 2
        BUZZER   : out std_logic;                      -- al modulo buzzer
        LED_OK   : out std_logic;                      -- clave correcta (queda prendido)
        LED_ERR  : out std_logic;                      -- alarma (clave mala)
        LED_STEP : out std_logic_vector(1 downto 0)    -- progreso de la clave (0..3)
    );
end SystemAlfa;

architecture arch_SystemAlfa of SystemAlfa is

    -- Ciberseguridad
    signal unlocked    : std_logic;
    signal freq_on_eff : std_logic;                   -- FREQ_ON habilitado por la clave
    constant USE_LOCK  : boolean := true;             -- false = la clave no bloquea nada (modo pruebas)

    -- RF1: divisor y seleccion de frecuencia
    signal f_05, f_1, f_2, f_3 : std_logic;
    signal freq_selected, freq_gated : std_logic;
    signal pairA_vec, pairB_vec, final_vec : std_logic_vector(3 downto 0);
    signal f05_vec, f1_vec, f2_vec, f3_vec : std_logic_vector(3 downto 0);
    signal pA_vec, pB_vec : std_logic_vector(3 downto 0);
    signal QF1, QF2, pulse_f : std_logic;
    signal RF : std_logic_vector(3 downto 0);

    -- Sensores IR
    signal pres_level, pres_pulse, size_level, size_pulse : std_logic;

    -- Color: TCS_Solo entrega directamente rojo / verde / azul
    signal col_start, col_done : std_logic;
    signal col_code : std_logic_vector(1 downto 0);
    signal c_rojo, c_verde, c_azul : std_logic;
    -- tiempo que se le da a TCS_Solo para confirmar el color de la pieza nueva
    -- (N_CONFIRM x 45 ms = 180 ms + margen) antes de avisar a la FSM con col_done
    constant T_COLOR_CYC : natural := 15000000;   -- 300 ms @ 50 MHz
    signal col_tmr  : natural range 0 to T_COLOR_CYC;
    signal col_wait : std_logic;

    -- FSM <-> RAM
    signal ram_addr_a, ram_addr_b : std_logic_vector(3 downto 0);
    signal ram_din, ram_dout_a, ram_dout_b : std_logic_vector(7 downto 0);
    signal ram_we : std_logic;

    -- Barrido de la RAM para displays
    signal scan : unsigned(3 downto 0);
    signal total_cnt, red_cnt, blue_cnt, green_cnt : std_logic_vector(3 downto 0);
    signal r_s, r_l, b_s, b_l, g_s, g_l : std_logic_vector(3 downto 0);

    function sum_mod10(a, b : std_logic_vector(3 downto 0)) return std_logic_vector is
        variable s : unsigned(4 downto 0);
    begin
        s := ('0' & unsigned(a)) + ('0' & unsigned(b));
        if s >= 10 then s := s - 10; end if;
        return std_logic_vector(s(3 downto 0));
    end function;
    signal last_color, last_size : std_logic_vector(3 downto 0);
    signal size_eff : std_logic;
    constant USE_SIZE : boolean := true;

    -- Velocidad (1,2,3) y tiempo de uso en segundos reales
    signal speed_code : std_logic_vector(3 downto 0);
    signal speed_sel  : std_logic_vector(1 downto 0);
    signal sec_tmr    : natural range 0 to 49999999;
    signal sec_cnt    : unsigned(3 downto 0);

    -- Datos finales a los displays
    signal last_color_disp : std_logic_vector(3 downto 0);
    signal disp1_data, disp2_data, disp3_data, disp4_data : std_logic_vector(3 downto 0);

    -- Servos: presencia -> color valido -> tamano decide cual se mueve
    signal size_lat   : std_logic;                    -- tamano de la pieza actual
    signal servo_go   : std_logic;                    -- orden de movimiento activa
    signal servo_sel  : std_logic;                    -- '0' servo 1 (pequena), '1' servo 2 (grande)
    constant SERVO_HOLD_CYC : natural := 2500000;     -- 50 ms: minimo que se mantiene la orden
    signal servo_hold : natural range 0 to SERVO_HOLD_CYC;
    signal sw_servo1, sw_servo2 : std_logic;

    component Divisor_Frecuencia
        port (
            Clk     : in  std_logic;
            out_05, out_1, out_2, out_3, out_sys : out std_logic
        );
    end component;

    component ContadorAscendente
        port (
            Clock, reset : in  std_logic;
            EN           : in  std_logic;
            CNT          : out std_logic_vector(3 downto 0)
        );
    end component;

    component mux2
        port (
            X, Y : in  std_logic_vector(3 downto 0);
            S    : in  std_logic;
            m    : out std_logic_vector(3 downto 0)
        );
    end component;

begin

    ----------------------------------------------------------------
    -- Ciberseguridad: clave B0 -> B0 -> B1 -> B2 para habilitar el sistema.
    -- Mientras no se ponga la clave, freq_on_eff = '0' y la banda, el
    -- selector de frecuencia y el contador de segundos quedan apagados.
    ----------------------------------------------------------------
    CLAVE: entity work.Ciberseguridad
        port map (Clk => CLK, Rst => RST, Btn => BTN,
                  Unlocked => unlocked, Buzzer => BUZZER,
                  Led_Ok => LED_OK, Led_Err => LED_ERR, Step => LED_STEP);

    freq_on_eff <= (FREQ_ON and unlocked) when USE_LOCK else FREQ_ON;

    ----------------------------------------------------------------
    -- RF1: divisor y seleccion de frecuencia
    ----------------------------------------------------------------
    DIV: Divisor_Frecuencia
        port map (Clk => CLK, out_05 => f_05, out_1 => f_1,
                  out_2 => f_2, out_3 => f_3, out_sys => open);

    -- vectores auxiliares (Quartus no admite expresiones no estaticas en el port map)
    f05_vec <= (others => f_05);
    f1_vec  <= (others => f_1);
    f2_vec  <= (others => f_2);
    f3_vec  <= (others => f_3);
    pA_vec  <= (others => pairA_vec(0));
    pB_vec  <= (others => pairB_vec(0));

    MUX_FA: mux2 port map (X => f2_vec, Y => f1_vec,
                           S => FREQ_SEL(1), m => pairA_vec);
    MUX_FB: mux2 port map (X => f3_vec, Y => f05_vec,
                           S => FREQ_SEL(1), m => pairB_vec);
    MUX_FINAL: mux2 port map (X => pA_vec, Y => pB_vec,
                              S => FREQ_SEL(2), m => final_vec);

    freq_selected <= final_vec(0);
    freq_gated    <= freq_selected when freq_on_eff = '1' else '0';
    FRECUENCIA    <= freq_gated;
    Led_CLK       <= freq_gated;

    process (CLK, RST)
    begin
        if RST = '0' then
            QF1 <= '0'; QF2 <= '0';
        elsif rising_edge(CLK) then
            QF1 <= freq_gated;
            QF2 <= QF1;
        end if;
    end process;
    pulse_f <= QF1 and (not QF2);

    CONT_F: ContadorAscendente
        port map (Clock => CLK, reset => RST, EN => pulse_f, CNT => RF);

    ----------------------------------------------------------------
    -- Sensores infrarrojos
    ----------------------------------------------------------------
    IR_P: entity work.Sync_Debounce
        generic map (ACTIVE_LOW => false, DEB_CYC => 500000)
        port map (Clk => CLK, Rst => RST, Din => IR_PRES,
                  Level => pres_level, Rise => pres_pulse);

    IR_S: entity work.Sync_Debounce
        generic map (ACTIVE_LOW => false, DEB_CYC => 500000)
        port map (Clk => CLK, Rst => RST, Din => IR_SIZE,
                  Level => size_level, Rise => size_pulse);

    -- LEDs de color: salen directamente de TCS_Solo
    LED_ROJO  <= c_rojo;
    LED_VERDE <= c_verde;
    LED_AZUL  <= c_azul;

    LED_OBJETO <= pres_level;
    size_eff   <= size_level when USE_SIZE else '0';

    ----------------------------------------------------------------
    -- Sensor de color: TCS_Solo (mide siempre, confirma N lecturas y
    -- mantiene encendido el LED del color ganador; todo apagado = NI)
    ----------------------------------------------------------------
    TCS: entity work.TCS_Solo
        port map (
            CLK => CLK, RST => RST, TCS_OUT => TCS_OUT,
            TCS_S0 => TCS_S0, TCS_S1 => TCS_S1, TCS_S2 => TCS_S2, TCS_S3 => TCS_S3,
            TCS_OE => TCS_OE,
            LED_ROJO => c_rojo, LED_AZUL => c_azul, LED_VERDE => c_verde);

    -- codigo de color para la FSM y la RAM: 00 NI, 01 rojo, 10 verde, 11 azul
    col_code <= "01" when c_rojo  = '1' else
                "10" when c_verde = '1' else
                "11" when c_azul  = '1' else
                "00";

    -- col_done: la FSM pide medir con col_start; se espera T_COLOR_CYC para que
    -- TCS_Solo confirme el color de la pieza nueva y entonces se da el pulso.
    process (CLK, RST)
    begin
        if RST = '0' then
            col_tmr  <= 0;
            col_wait <= '0';
            col_done <= '0';
        elsif rising_edge(CLK) then
            col_done <= '0';
            if col_start = '1' then
                col_wait <= '1';
                col_tmr  <= 0;
            elsif col_wait = '1' then
                if col_tmr = T_COLOR_CYC - 1 then
                    col_wait <= '0';
                    col_done <= '1';
                else
                    col_tmr <= col_tmr + 1;
                end if;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- FSM + RAM
    ----------------------------------------------------------------
    FSM: entity work.FSM_Control
        port map (
            Clk => CLK, Rst => RST,
            Pres_Pulse => pres_pulse, Pres_Level => pres_level, Size_Level => size_eff,
            Col_Start => col_start, Col_Done => col_done, Col_Code => col_code,
            Ram_Addr => ram_addr_a, Ram_Din => ram_din, Ram_Dout => ram_dout_a,
            Ram_We => ram_we, State_Code => LED_ESTADO);

    RAM: entity work.RAM_Conteo
        port map (
            Clk => CLK, We => ram_we,
            Addr_A => ram_addr_a, Din => ram_din, Dout_A => ram_dout_a,
            Addr_B => ram_addr_b, Dout_B => ram_dout_b);

    ----------------------------------------------------------------
    -- Servos del brazo (dos Servo_180), en serie con el sistema:
    --   1. presencia : la FSM solo pide color tras detectar una pieza
    --   2. color     : al llegar col_done se mira col_code; si es NI (00)
    --                  ningun servo se mueve
    --   3. tamano    : 0 -> servo 1   /   1 -> servo 2
    --   La orden dura al menos 50 ms y hasta que la pieza sale del sensor,
    --   asi cada pieza valida produce UN barrido del servo que le toca.
    ----------------------------------------------------------------
    process (CLK, RST)
    begin
        if RST = '0' then
            size_lat   <= '0';
            servo_go   <= '0';
            servo_sel  <= '0';
            servo_hold <= 0;
        elsif rising_edge(CLK) then
            -- tamano de la pieza: lo que marque el sensor al entrar, y '1' si el
            -- sensor de tamano se activa en cualquier momento mientras hay pieza
            if pres_pulse = '1' then
                size_lat <= size_eff;
            elsif pres_level = '1' and size_eff = '1' then
                size_lat <= '1';
            end if;

            -- disparo: color recibido y valido
            if col_done = '1' and col_code /= "00" then
                servo_go   <= '1';
                servo_sel  <= size_lat;
                servo_hold <= 0;
            elsif servo_go = '1' then
                if servo_hold < SERVO_HOLD_CYC then
                    servo_hold <= servo_hold + 1;
                elsif pres_level = '0' then
                    servo_go <= '0';                  -- la pieza salio: listo para la siguiente
                end if;
            end if;
        end if;
    end process;

    sw_servo1 <= servo_go and (not servo_sel);        -- tamano 0
    sw_servo2 <= servo_go and servo_sel;              -- tamano 1

    SERVO_A: entity work.Servo_180
        port map (Clk => CLK, Rst => RST, Sw => sw_servo1, Servo_Pwm => SERVO1_PWM);

    SERVO_B: entity work.Servo_180
        port map (Clk => CLK, Rst => RST, Sw => sw_servo2, Servo_Pwm => SERVO2_PWM);

    ----------------------------------------------------------------
    -- Barrido continuo de la RAM (puerto B) -> registros de display
    -- Mapa RAM: 0 total | 1 R peq | 2 R gde | 3 V peq | 4 V gde
    --           5 A peq | 6 A gde | 7 NI    | 8 ult. color | 9 ult. tamano
    -- En MODE 0 cada color muestra las piezas del tamano elegido con SEL_VIEW(2)
    ----------------------------------------------------------------
    with scan select
        ram_addr_b <= "0000" when "0000",   -- total
                      "0001" when "0001",   -- rojo peq
                      "0010" when "0010",   -- rojo gde
                      "0101" when "0011",   -- azul peq
                      "0110" when "0100",   -- azul gde
                      "0011" when "0101",   -- verde peq
                      "0100" when "0110",   -- verde gde
                      "1000" when "0111",   -- ultimo color
                      "1001" when others;   -- ultimo tamano

    process (CLK, RST)
    begin
        if RST = '0' then
            scan <= (others => '0');
            total_cnt <= (others => '0');
            r_s <= (others => '0'); r_l <= (others => '0');
            b_s <= (others => '0'); b_l <= (others => '0');
            g_s <= (others => '0'); g_l <= (others => '0');
            last_color <= (others => '0'); last_size <= (others => '0');
        elsif rising_edge(CLK) then
            case scan is
                when "0000" => total_cnt  <= ram_dout_b(3 downto 0);
                when "0001" => r_s        <= ram_dout_b(3 downto 0);
                when "0010" => r_l        <= ram_dout_b(3 downto 0);
                when "0011" => b_s        <= ram_dout_b(3 downto 0);
                when "0100" => b_l        <= ram_dout_b(3 downto 0);
                when "0101" => g_s        <= ram_dout_b(3 downto 0);
                when "0110" => g_l        <= ram_dout_b(3 downto 0);
                when "0111" => last_color <= ram_dout_b(3 downto 0);
                when others => last_size  <= ram_dout_b(3 downto 0);
            end case;
            if scan = 8 then scan <= (others => '0'); else scan <= scan + 1; end if;
        end if;
    end process;

    -- contador por color del tamano elegido con SEL_VIEW(2): '0' pequenas, '1' grandes
    red_cnt   <= r_s when SEL_VIEW(2) = '0' else r_l;
    blue_cnt  <= b_s when SEL_VIEW(2) = '0' else b_l;
    green_cnt <= g_s when SEL_VIEW(2) = '0' else g_l;

    ----------------------------------------------------------------
    -- Codigo de velocidad para el display 3: 1, 2 o 3
    -- 00->2Hz  01->1Hz  10->3Hz  11->0.5Hz (se muestra 0)
    ----------------------------------------------------------------
    speed_sel <= FREQ_SEL(2) & FREQ_SEL(1);
    process (speed_sel)
    begin
        case speed_sel is
            when "00"   => speed_code <= "0010";
            when "01"   => speed_code <= "0001";
            when "10"   => speed_code <= "0011";
            when others => speed_code <= "0000";
        end case;
    end process;

    ----------------------------------------------------------------
    -- Motor de la banda: componente Puente_H (el probado solo en la placa).
    -- Reset general RST, enable freq_on_eff (FREQ_ON + clave) y los switches
    -- FREQ_SEL directos:
    --   00 -> normal (60 %)      01 -> muy rapida (100 %)
    --   10 -> lenta  (35 %)      11 -> muy lenta  (20 %)
    ----------------------------------------------------------------
    CINTA: entity work.Puente_H
        port map (Clk => CLK, Rst => RST, FREQ_ON => freq_on_eff, FREQ_SEL => FREQ_SEL,
                  ENA => MOTOR_PWM, IN1 => MOTOR_IN1, IN2 => MOTOR_IN2);

    ----------------------------------------------------------------
    -- Tiempo de uso en segundos REALES (50 MHz), cuenta mientras freq_on_eff = '1'
    ----------------------------------------------------------------
    process (CLK, RST)
    begin
        if RST = '0' then
            sec_tmr <= 0; sec_cnt <= (others => '0');
        elsif rising_edge(CLK) then
            if freq_on_eff = '0' then
                sec_tmr <= 0; sec_cnt <= (others => '0');
            elsif sec_tmr = 49999999 then
                sec_tmr <= 0;
                if sec_cnt = 9 then sec_cnt <= (others => '0');
                else sec_cnt <= sec_cnt + 1; end if;
            else
                sec_tmr <= sec_tmr + 1;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- Ultimo color como lo quieres ver: 1 rojo, 2 azul, 3 verde (0 = NI)
    -- (en la RAM: 01 = R, 10 = V, 11 = A)
    ----------------------------------------------------------------
    with last_color(1 downto 0) select
        last_color_disp <= "0001" when "01",   -- rojo  -> 1
                           "0011" when "10",   -- verde -> 3
                           "0010" when others; -- azul  -> 2 (11)  (00 se corrige abajo)

    ----------------------------------------------------------------
    -- Seleccion de lo que muestra cada display
    --   MODE 0: total | rojas | azules | verdes
    --   MODE 1: ultimo color | ultimo tamano | velocidad | segundos
    ----------------------------------------------------------------
    disp1_data <= total_cnt when MODE = '0' else
                  "0000"    when last_color(1 downto 0) = "00" else last_color_disp;
    disp2_data <= red_cnt   when MODE = '0' else ("000" & last_size(0));
    disp3_data <= blue_cnt  when MODE = '0' else speed_code;
    disp4_data <= green_cnt when MODE = '0' else std_logic_vector(sec_cnt);

    SEG1: entity work.ROM_Seg port map (Addr => disp1_data, Data => DIS1);
    SEG2: entity work.ROM_Seg port map (Addr => disp2_data, Data => DIS2);
    SEG3: entity work.ROM_Seg port map (Addr => disp3_data, Data => DIS3);
    SEG4: entity work.ROM_Seg port map (Addr => disp4_data, Data => DIS4);

end arch_SystemAlfa;