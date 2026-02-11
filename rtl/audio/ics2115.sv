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
// 32 Voice Polyphony (Implementing infrastructure)

reg [7:0] regs [0:255];
reg [7:0] cur_reg_addr;

// Register access logic (Indirect)
always @(posedge clk) begin
    if (reset) begin
        cur_reg_addr <= 0;
    end else if (we) begin
        case (addr)
            2'b00: cur_reg_addr <= din;
            2'b01: regs[cur_reg_addr] <= din;
        endcase
    end
end

assign dout = (addr == 2'b01) ? regs[cur_reg_addr] : 8'h00;

// Simple Sample Playback FSM (Voice 0 placeholder)
reg [1:0] state;
localparam IDLE  = 2'd0;
localparam FETCH = 2'd1;
localparam PLAY  = 2'd2;

reg [23:0] sample_addr;
reg [15:0] last_sample_l, last_sample_r;

always @(posedge clk) begin
    if (reset) begin
        state <= IDLE;
        sdram_rd <= 0;
        sample_addr <= 0;
    end else begin
        case (state)
            IDLE: begin
                // Trig logic placeholder
                if (regs[8'h40][0]) begin // Assume bit 0 of reg 0x40 is "play"
                    state <= FETCH;
                    sample_addr <= {regs[8'h41], regs[8'h42], regs[8'h43]}; // Start Addr
                end
            end
            
            FETCH: begin
                sdram_rd <= 1;
                sdram_addr <= {5'b0, sample_addr};
                if (sdram_dout_ready) begin
                    sdram_rd <= 0;
                    last_sample_l <= ddram_dout[15:0];
                    last_sample_r <= ddram_dout[31:16];
                    state <= PLAY;
                end
            end
            
            PLAY: begin
                // Wait for speaker sync or just loop for now
                if (!regs[8'h40][0]) state <= IDLE;
                else begin
                    sample_addr <= sample_addr + 1'd1;
                    state <= FETCH;
                end
            end
        endcase
    end
end

assign sample_l = last_sample_l;
assign sample_r = last_sample_r;

endmodule
