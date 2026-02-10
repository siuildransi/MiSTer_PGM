module pgm_video (
    input         clk,
    input         reset,

    // Video Data from Core
    output reg [13:1] vram_addr,
    input      [15:0] vram_dout,
    output reg [12:1] pal_addr,
    input      [15:0] pal_dout,
    input      [15:0] vregs [0:31],

    // Video Output
    output        hs,
    output        vs,
    output [7:0]  r,
    output [7:0]  g,
    output [7:0]  b,
    output        blank_n
);

// PGM Native Resolution: 448x224
// We'll use a 25.175MHz (VGA) or similar for now, but PGM uses specific clocks.
// For now, let's stick to the 640x480 timing but center the PGM 448x224 image.

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

assign hs = ~(h_cnt >= 656 && h_cnt < 752);
assign vs = ~(v_cnt >= 490 && v_cnt < 492);
assign blank_n = (h_cnt < 640 && v_cnt < 480);

// --- Tilemap Fetching Logic (Simplistic Start) ---
// PGM Tile Maps:
// Background: 64x32 tiles (8x8 pixels each) = 512x256 pixels
// Or 128x32. Let's assume 64x32 for now.

wire [9:0] x = h_cnt;
wire [9:0] y = v_cnt;

// Offset to center 448x224 in 640x480
wire [9:0] px = x - 10'd96;
wire [9:0] py = y - 10'd128;
wire active = (x >= 96 && x < 544 && y >= 128 && y < 352);

// Calculate tile address
// Each tile is 8x8 pixels.
// tile_x = px / 8, tile_y = py / 8
// addr = tile_y * 64 + tile_x
always @(*) begin
    vram_addr = {py[7:3], px[8:3]}; // Simplistic mapping
    pal_addr = vram_dout[11:0];      // Placeholder for palette index
end

// Output
assign r = active ? pal_dout[15:11] << 3 : 8'h00;
assign g = active ? pal_dout[10:5]  << 2 : 8'h00;
assign b = active ? pal_dout[4:0]   << 3 : 8'h00;

endmodule
