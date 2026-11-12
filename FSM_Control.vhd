-- FSM principal, escrita en el estilo de la clase (3 procesos):
--   1) STATE_MEMORY     : registro de estado   (current_state <= next_state)
--   2) NEXT_STATE_LOGIC : logica del estado siguiente (case)
--   3) OUTPUT_LOGIC     : logica de salida (case)
-- Mas un proceso DATA_REGS para guardar tamano y color de la pieza actual.
--
-- Flujo: presencia (guarda tamano) -> medir color -> contar en la RAM
--
-- Mapa de la RAM (cada posicion cuenta 0..9):
--   0 = total
--   1 = rojo pequeno   2 = rojo grande
--   3 = verde pequeno  4 = verde grande
--   5 = azul pequeno   6 = azul grande
--   7 = NI (no identificado)
--   8 = ultimo color   9 = ultimo tamano
library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.numeric_std.ALL;

entity FSM_Control is
    port (
        Clk, Rst   : in  std_logic;   -- Rst activo en '0'
        Pres_Pulse : in  std_logic;   -- llego una pieza (IR presencia)
        Pres_Level : in  std_logic;   -- la pieza sigue ahi
        Size_Level : in  std_logic;   -- IR tamano: '1' = grande, '0' = pequena
        Col_Start  : out std_logic;
        Col_Done   : in  std_logic;
        Col_Code   : in  std_logic_vector(1 downto 0);
        Ram_Addr   : out std_logic_vector(3 downto 0);
        Ram_Din    : out std_logic_vector(7 downto 0);
        Ram_Dout   : in  std_logic_vector(7 downto 0);
        Ram_We     : out std_logic;
        State_Code : out std_logic_vector(3 downto 0)
    );
end FSM_Control;

architecture arch of FSM_Control is

    -- Modelado de los estados con tipo enumerado
    type State_Type is (S_CLEAR, S_IDLE, S_MEAS_START, S_MEAS_WAIT,
                        S_INC_TOTAL, S_INC_COLOR, S_WR_LASTC, S_WR_LASTS, S_WAIT_CLEAR);
    signal current_state, next_state : State_Type;

    signal clr_cnt : unsigned(3 downto 0);
    signal color_r : std_logic_vector(1 downto 0);
    signal size_r  : std_logic;

    -- incrementa 0..9 y vuelve a 0
    function inc_bcd(v : std_logic_vector(7 downto 0)) return std_logic_vector is
    begin
        if unsigned(v(3 downto 0)) >= 9 then
            return x"00";
        else
            return std_logic_vector(unsigned(v) + 1);
        end if;
    end function;

begin

    ----------------------------------------------------------------
    -- 1) Memoria de estado
    ----------------------------------------------------------------
    STATE_MEMORY : process (Clk, Rst)
    begin
        if Rst = '0' then
            current_state <= S_CLEAR;
        elsif rising_edge(Clk) then
            current_state <= next_state;
        end if;
    end process;

    ----------------------------------------------------------------
    -- 2) Logica del estado siguiente
    ----------------------------------------------------------------
    NEXT_STATE_LOGIC : process (current_state, clr_cnt, Pres_Pulse, Pres_Level, Col_Done)
    begin
        case current_state is
            when S_CLEAR =>                       -- borra la RAM al arrancar
                if clr_cnt = 15 then
                    next_state <= S_IDLE;
                else
                    next_state <= S_CLEAR;
                end if;

            when S_IDLE =>                        -- espera una pieza
                if Pres_Pulse = '1' then
                    next_state <= S_MEAS_START;
                else
                    next_state <= S_IDLE;
                end if;

            when S_MEAS_START => next_state <= S_MEAS_WAIT;   -- manda medir al TCS

            when S_MEAS_WAIT =>                   -- espera el color
                if Col_Done = '1' then
                    next_state <= S_INC_TOTAL;
                else
                    next_state <= S_MEAS_WAIT;
                end if;

            when S_INC_TOTAL => next_state <= S_INC_COLOR;
            when S_INC_COLOR => next_state <= S_WR_LASTC;
            when S_WR_LASTC  => next_state <= S_WR_LASTS;
            when S_WR_LASTS  => next_state <= S_WAIT_CLEAR;

            when S_WAIT_CLEAR =>                  -- espera a que la pieza salga
                if Pres_Level = '0' then
                    next_state <= S_IDLE;
                else
                    next_state <= S_WAIT_CLEAR;
                end if;

            when others => next_state <= S_CLEAR;
        end case;
    end process;

    ----------------------------------------------------------------
    -- Registros de datos: contador de borrado, tamano y color
    ----------------------------------------------------------------
    DATA_REGS : process (Clk, Rst)
    begin
        if Rst = '0' then
            clr_cnt <= (others => '0');
            color_r <= "00";
            size_r  <= '0';
        elsif rising_edge(Clk) then
            if current_state = S_CLEAR then
                if clr_cnt = 15 then
                    clr_cnt <= (others => '0');
                else
                    clr_cnt <= clr_cnt + 1;
                end if;
            end if;
            if current_state = S_IDLE and Pres_Pulse = '1' then
                size_r <= Size_Level;            -- presencia GUARDA el tamano
            end if;
            if current_state = S_MEAS_WAIT and Col_Done = '1' then
                color_r <= Col_Code;             -- el TCS entrega el color
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- 3) Logica de salida
    ----------------------------------------------------------------
    OUTPUT_LOGIC : process (current_state, clr_cnt, color_r, size_r, Ram_Dout)
    begin
        Ram_Addr  <= "0000";
        Ram_Din   <= x"00";
        Ram_We    <= '0';
        Col_Start <= '0';
        case current_state is
            when S_CLEAR =>
                Ram_Addr <= std_logic_vector(clr_cnt); Ram_Din <= x"00"; Ram_We <= '1';

            when S_MEAS_START =>
                Col_Start <= '1';

            when S_INC_TOTAL =>
                Ram_Addr <= "0000"; Ram_Din <= inc_bcd(Ram_Dout); Ram_We <= '1';

            when S_INC_COLOR =>                   -- contador por color Y tamano
                if color_r = "00" then
                    Ram_Addr <= "0111";                              -- NI
                elsif color_r = "01" then
                    if size_r = '0' then Ram_Addr <= "0001"; else Ram_Addr <= "0010"; end if;
                elsif color_r = "10" then
                    if size_r = '0' then Ram_Addr <= "0011"; else Ram_Addr <= "0100"; end if;
                else
                    if size_r = '0' then Ram_Addr <= "0101"; else Ram_Addr <= "0110"; end if;
                end if;
                Ram_Din <= inc_bcd(Ram_Dout); Ram_We <= '1';

            when S_WR_LASTC =>
                Ram_Addr <= "1000"; Ram_Din <= "000000" & color_r; Ram_We <= '1';

            when S_WR_LASTS =>
                Ram_Addr <= "1001"; Ram_Din <= "0000000" & size_r; Ram_We <= '1';

            when others => null;
        end case;
    end process;

    State_Code <= std_logic_vector(to_unsigned(State_Type'pos(current_state), 4));

end arch;