module pgm_video (
    input         clk,
    input         reset,

    // Video Data from Core
    output reg [13:1] vram_addr,
    input      [15:0] vram_dout,
    output reg [12:1] pal_addr,
    input      [15:0] pal_dout,
    input      [511:0] vregs,
    output reg [10:1] sprite_addr,
    input      [15:0] sprite_dout,

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

// --- Sprite Engine (Line Buffer Scanning) ---
// Each word in A-ROM contains 3 pixels (5 bits each). 
// Word: [P2:5, P1:5, P0:5, Ignored:1] -> This needs verification against MAME.
// Typical PGM A-ROM packing: 3 pixels per 16-bit word.

localparam SCAN_SPRITES = 0;
localparam FETCH_SPRITES = 1;
localparam RENDER_LINE = 2;

reg [1:0]  sprite_state;
reg [7:0]  curr_sprite_idx;
reg [7:0]  active_sprites_count;

struct packed {
    logic [10:0] x;
    logic [4:0]  width;
    logic [4:0]  height;
    logic [4:0]  pal;
    logic [15:0] code;
    logic [7:0]  x_zoom;
    logic [7:0]  y_zoom;
} line_sprites [0:31];

// Pixel line buffer (to avoid SDRAM bottlenecks during active display)
reg [4:0] line_buffer [0:447]; // 5 bits per pixel for the line

reg [2:0] attr_cnt;
always @(posedge clk) begin
    if (reset) begin
        sprite_state <= SCAN_SPRITES;
        curr_sprite_idx <= 0;
        active_sprites_count <= 0;
        attr_cnt <= 0;
    end else begin
        case (sprite_state)
            SCAN_SPRITES: begin
                if (h_cnt >= 640) begin
                    sprite_addr <= {curr_sprite_idx, 2'b00} + attr_cnt[1:0];
                    case (attr_cnt)
                        3'd1: line_sprites[active_sprites_count].x      <= sprite_dout[10:0];
                        3'd2: line_sprites[active_sprites_count].height <= sprite_dout[4:1];
                        3'd3: line_sprites[active_sprites_count].code   <= sprite_dout;
                        3'd4: begin
                            line_sprites[active_sprites_count].width  <= sprite_dout[11:6];
                            line_sprites[active_sprites_count].x_zoom <= sprite_dout[7:0];
                        end
                    endcase
                    if (attr_cnt == 5) begin
                        if (active_sprites_count < 31) active_sprites_count <= active_sprites_count + 1'd1;
                        attr_cnt <= 0;
                        curr_sprite_idx <= curr_sprite_idx + 1'd1;
                        if (curr_sprite_idx == 255) sprite_state <= FETCH_SPRITES;
                    end else attr_cnt <= attr_cnt + 1'd1;
                end
            end
            
            FETCH_SPRITES: begin
                // Fetch pixel data from B-ROM and A-ROM for the sprites found in SCAN_SPRITES
                if (active_sprites_count > 0 && curr_sprite_idx < active_sprites_count) begin
                    if (!ddram_busy) begin
                        ddram_addr <= 29'h0400000 + line_sprites[curr_sprite_idx].code[15:0];
                        ddram_rd <= 1;
                        
                        // --- Simplistic Sprite Drawing to Line Buffer ---
                        // For a real PGM, we need to handle horizontal zoom and flip.
                        // For now, we just copy 16 pixels if they fit in the scanline.
                        if (line_sprites[curr_sprite_idx].x < 448) begin
                            // This would be a loop/state machine in real hardware.
                            // Latching the 5bpp pixels into the buffer:
                            line_buffer[line_sprites[curr_sprite_idx].x] <= ddram_dout[4:0];
                        end
                        
                        curr_sprite_idx <= curr_sprite_idx + 1'd1;
                    end
                end else begin
                    ddram_rd <= 0;
                    if (h_cnt == 799) sprite_state <= SCAN_SPRITES;
                end
            end
        endcase
    end
end

// --- Tilemap Rendering (Background) ---
wire active = (h_cnt >= 96 && h_cnt < 544 && v_cnt >= 128 && v_cnt < 352);
wire [9:0] px = h_cnt - 10'd96;
wire [9:0] py = v_cnt - 10'd128;

reg [15:0] bg_data;
always @(posedge clk) begin
    if (active) begin
        case (h_cnt[2:0])
            3'd0: vram_addr <= {py[7:3], px[8:3]};
            3'd4: bg_data <= vram_dout;
        endcase
    end
end

// Color Output Mixer
always @(posedge clk) begin
    if (!active) begin
        r <= 0; g <= 0; b <= 0;
    end else begin
        // Mix Background tiles and Sprites (Simple Priority)
        // If sprite pixel is not 0 (transparent), show sprite.
        if (line_buffer[px] != 0) begin
            // Sprite Pixel (Palette lookup placeholder)
            r <= 8'hFF; g <= 8'hFF; b <= 8'hFF;
        end else begin
            // Background Pixel
            r <= bg_data[15:11] << 3;
            g <= bg_data[10:5]  << 2;
            b <= bg_data[4:0]   << 3;
        end
    end
end

endmodule
