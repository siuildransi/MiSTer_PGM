module ics2115 (
    input         clk,
    input         reset,
    
    input  [1:0]  addr,
    input  [7:0]  din,
    output [7:0]  dout,
    input         we,
    input         re,
    
    // SDRAM Interface (Samples)
    output reg        sdram_rd,
    output reg [28:0] sdram_addr,
    input      [63:0] sdram_dout,
    input             sdram_busy,
    input             sdram_dout_ready,

    output [15:0] sample_l,
    output [15:0] sample_r
);

// ICS2115 (Wavetable Synthesizer)
// 32 Voice Polyphony (TDM Implementation)

reg [7:0] regs [0:255];
reg [7:0] cur_reg_addr;

// Nota: La escritura a cur_reg_addr y regs[] se realiza en el bloque TDM principal (abajo)
// para evitar múltiples drivers sobre las mismas señales.

assign dout = (addr == 2'b01) ? regs[cur_reg_addr] : 8'h00;

// --- 32-Voice TDM Engine ---
reg [4:0]  voice_cnt;       // 0-31 voices
reg [4:0]  selected_voice;  // Voz seleccionada para acceso host (Reg 0x08)
reg [1:0]  tdm_state;
localparam TDM_IDLE   = 2'd0;
localparam TDM_FETCH  = 2'd1;
localparam TDM_MIX    = 2'd2;
localparam TDM_FINISH = 2'd3;

// Voice States (Simplified for now)
reg [23:0] v_addr   [0:31];
reg [15:0] v_incr   [0:31];
reg [7:0]  v_vol_l  [0:31];
reg [7:0]  v_vol_r  [0:31];
reg [31:0] v_active;        // Bitmask for active voices

// Mixing Accumulators
reg signed [23:0] mix_l, mix_r;
reg [15:0] final_l, final_r;

integer v;
always @(posedge clk) begin
    if (reset) begin
        voice_cnt <= 0;
        final_l <= 0;
        final_r <= 0;
        selected_voice <= 0;
        tdm_state <= TDM_IDLE;
        v_active <= 0;
        mix_l <= 0;
        mix_r <= 0;
        sdram_rd <= 0;
        for (v=0; v<32; v=v+1) begin
            v_addr[v] <= 0;
            v_incr[v] <= 0;
        end
    end else begin
        // --- Host Register Interface (Z80) ---
        if (we) begin
            case (addr)
                2'b00: cur_reg_addr <= din;
                2'b01: begin
                    regs[cur_reg_addr] <= din;
                    case (cur_reg_addr)
                        8'h08: selected_voice <= din[4:0];
                        8'h40: v_active[selected_voice] <= din[0];
                        8'h41: v_addr[selected_voice][7:0] <= din;
                        8'h42: v_addr[selected_voice][15:8] <= din;
                        8'h43: v_addr[selected_voice][23:16] <= din;
                    endcase
                end
            endcase
        end

        // --- TDM Mixing FSM ---
        case (tdm_state)
            TDM_IDLE: begin
                // Comenzar ciclo de mezcla cada vez que voice_cnt vuelve a 0
                // (En un diseño real esto se sincronizaría con una señal de 33kHz)
                voice_cnt <= 0;
                mix_l <= 0;
                mix_r <= 0;
                tdm_state <= TDM_FETCH;
            end

            TDM_FETCH: begin
                if (v_active[voice_cnt]) begin
                    sdram_rd <= 1;
                    // Offset Audio Samples (W-ROM): 0x3100000 bytes = 0x620000 words
                    sdram_addr <= 29'h620000 + {5'b0, v_addr[voice_cnt]};
                    if (sdram_dout_ready) begin
                        sdram_rd <= 0;
                        tdm_state <= TDM_MIX;
                    end
                end else begin
                    // Voz inactiva, saltar a la siguiente
                    if (voice_cnt == 31) tdm_state <= TDM_FINISH;
                    else voice_cnt <= voice_cnt + 1'd1;
                end
            end

            TDM_MIX: begin
                // Mezcla de canal Izquierdo (16-bit PCM sign-extended)
                mix_l <= mix_l + $signed(sdram_dout[15:0]);
                // Mezcla de canal Derecho
                mix_r <= mix_r + $signed(sdram_dout[31:16]);
                
                // Avanzar dirección del puntero
                v_addr[voice_cnt] <= v_addr[voice_cnt] + 1'd1; 
                
                if (voice_cnt == 31) tdm_state <= TDM_FINISH;
                else begin
                    voice_cnt <= voice_cnt + 1'd1;
                    tdm_state <= TDM_FETCH;
                end
            end

            TDM_FINISH: begin
                // Aplicar saturación y volumen global (simplificado)
                if (mix_l > 24'sd32767)       final_l <= 16'sh7FFF;
                else if (mix_l < -24'sd32768) final_l <= 16'sh8000;
                else                          final_l <= mix_l[15:0];

                if (mix_r > 24'sd32767)       final_r <= 16'sh7FFF;
                else if (mix_r < -24'sd32768) final_r <= 16'sh8000;
                else                          final_r <= mix_r[15:0];
                tdm_state <= TDM_IDLE;
            end
        endcase
    end
end

assign sample_l = final_l;
assign sample_r = final_r;

endmodule
