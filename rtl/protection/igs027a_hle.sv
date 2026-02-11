/*
    IGS027A HLE Protection Module
    Emula el comportamiento del coprocesador ARM7 (Type 3) para juegos PGM.
    Referencia: MAME pgmprot_igs027a_type3.cpp
*/

module igs027a_hle (
    input             clk,
    input             reset,
    
    input      [3:0]  addr,    // adr[4:1] del bus 68k
    input      [15:0] din,
    output reg [15:0] dout,
    input             we,
    input             re,
    
    output reg        dtack_n  // DTACK para la 68k
);

// Registros internos de comunicación
reg [15:0] command_reg;
reg [15:0] status_reg;
reg [15:0] data_reg[0:3];

// FSM para el manejo de comandos
localparam STATE_IDLE    = 2'd0;
localparam STATE_PROCESS = 2'd1;
localparam STATE_DONE    = 2'd2;

reg [1:0] state;

always @(posedge clk) begin
    if (reset) begin
        state <= STATE_IDLE;
        dtack_n <= 1'b1;
        status_reg <= 16'h0000;
        command_reg <= 16'h0000;
        dout <= 16'hFFFF;
    end else begin
        dtack_n <= 1'b1; // Por defecto no asertado
        
        // Escritura desde 68k
        if (we) begin
            dtack_n <= 1'b0;
            case (addr[3:0])
                4'h0: command_reg <= din;
                4'h1: data_reg[0] <= din;
                4'h2: data_reg[1] <= din;
                4'h3: data_reg[2] <= din;
                default: ;
            endcase
            
            // Si escribimos al registro de comando, disparamos la lógica "HLE"
            if (addr[3:0] == 4'h0) begin
                state <= STATE_PROCESS;
            end
        end
        
        // Lectura desde 68k
        if (re) begin
            dtack_n <= 1'b0;
            case (addr[3:0])
                4'h0: dout <= status_reg;
                4'h1: dout <= data_reg[0];
                4'h2: dout <= data_reg[1];
                4'h3: dout <= data_reg[2];
                default: dout <= 16'hFFFF;
            endcase
        end
        
        // Lógica de procesamiento HLE (Simulación de respuestas ARM7)
        case (state)
            STATE_PROCESS: begin
                case (command_reg)
                    16'h0011: begin // Initialize / Protection Check
                        data_reg[0] <= 16'h55AA;
                        data_reg[1] <= 16'hAA55;
                        status_reg[0] <= 1'b1; // Done
                    end
                    16'h0012: begin // Write Internal RAM
                        status_reg[0] <= 1'b1;
                    end
                    16'h0013: begin // Read Internal RAM
                        data_reg[0] <= data_reg[0]; // Mirror back for now
                        status_reg[0] <= 1'b1;
                    end
                    16'h0014: begin // Sprite Processing Trigger
                        // En el hardware real, aquí el ARM procesa listas.
                        // Para HLE inicial, simplemente devolvemos Done.
                        status_reg[0] <= 1'b1;
                    end
                    default: begin
                        status_reg[0] <= 1'b1;
                    end
                endcase
                command_reg <= 16'h0000;
                state <= STATE_DONE;
            end
            
            STATE_DONE: begin
                // Done set in status_reg[0] will persist until next command
                state <= STATE_IDLE;
            end
        endcase
    end
end

endmodule
