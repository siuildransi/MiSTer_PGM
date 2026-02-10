module pgm_video (
    input         clk,
    input         reset,

    // Video Data from Core
    output reg [13:1] vram_addr,
    input      [15:0] vram_dout,
    output reg [12:1] pal_addr,
    input      [15:0] pal_dout,
    input      [15:0] vregs [0:31],

    // SDRAM (Graphic Data)
    output reg        ddram_rd,
    output reg [28:0] ddram_addr,
    input      [63:0] ddram_dout,
    input             ddram_busy,

    // Video Output
    output reg        hs,
    output reg        vs,
    output reg [7:0]  r,
    output reg [7:0]  g,
    output reg [7:0]  b,
    output reg        blank_n
);

// PGM Timings: 448x224 (centered in 640x480 for now)
reg [9:0] h_cnt;
reg [9:0] v_cnt;

always @(posedge clk) begin
    if (reset) begin
        h_cnt <= 0;
        v_cnt <= 0;
    end else begin
        if (h_cnt == 799) begin
            h_cnt <= 0;
            if (v_cnt == 524) v_cnt <= 0;
            else v_cnt <= v_cnt + 1'd1;
        end else h_cnt <= h_cnt + 1'd1;
    end
end

// Signals
wire hs_w = ~(h_cnt >= 656 && h_cnt < 752);
wire vs_w = ~(v_cnt >= 490 && v_cnt < 492);
wire blank_n_w = (h_cnt < 640 && v_cnt < 480);

always @(posedge clk) begin
    hs <= hs_w;
    vs <= vs_w;
    blank_n <= blank_n_w;
end

// --- Tilemap Rendering State Machine ---
// Fetching sequence:
// 1. Calculate Tile Address in VRAM
// 2. Fetch Tile ID from VRAM
// 3. Calculate SDRAM address for bitplanes
// 4. Request SDRAM data
// 5. Latch data for 8 or 16 pixels

wire [9:0] px = h_cnt - 10'd96;
wire [9:0] py = v_cnt - 10'd128;
wire active = (h_cnt >= 96 && h_cnt < 544 && v_cnt >= 128 && v_cnt < 352);

reg [15:0] tile_data_latch;
reg [2:0]  pixel_idx;

always @(posedge clk) begin
    if (reset) begin
        ddram_rd <= 0;
        vram_addr <= 0;
    end else if (active) begin
        // Simple state machine based on h_cnt[2:0]
        case (h_cnt[2:0])
            3'd0: begin
                vram_addr <= {py[7:3], px[8:3]}; // VRAM lookup for tile index
            end
            3'd2: begin
                // Calculate SDRAM address (Tile ID * bits per tile)
                // PGM tiles are 16x16, 5bpp usually.
                ddram_addr <= {vram_dout[11:0], py[3:0], 1'b0}; 
                ddram_rd <= 1;
            end
            3'd4: begin
                ddram_rd <= 0;
                if (!ddram_busy) tile_data_latch <= ddram_dout[15:0]; // Placeholder
            end
        endcase
    end
end

// Color Output
always @(posedge clk) begin
    if (!active) begin
        r <= 0; g <= 0; b <= 0;
    end else begin
        // Use tile_data_latch to pick a color
        // For now, just a gradient based on the latch to verify fetching
        r <= tile_data_latch[15:11] << 3;
        g <= tile_data_latch[10:5]  << 2;
        b <= tile_data_latch[4:0]   << 3;
    end
end

endmodule
