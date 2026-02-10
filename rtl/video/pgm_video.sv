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

reg hs_d1, vs_d1, blank_n_d1;

always @(posedge clk) begin
    // Stage 1
    hs_d1 <= hs_w;
    vs_d1 <= vs_w;
    blank_n_d1 <= blank_n_w;
    
    // Stage 2 (Output)
    hs <= hs_d1;
    vs <= vs_d1;
    blank_n <= blank_n_d1;
end

// --- Sprite Engine (Line Buffer Scanning) ---
// Each word in A-ROM contains 3 pixels (5 bits each). 
// Word: [P2:5, P1:5, P0:5, Ignored:1] -> This needs verification against MAME.
// Typical PGM A-ROM packing: 3 pixels per 16-bit word.

localparam SCAN_SPRITES  = 2'd0;
localparam FETCH_SPRITES = 2'd1;
localparam CLEAR_BUFFER  = 2'd2;

reg [1:0]  sprite_state;
reg [9:0]  px_sub_cnt;
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

// Pixel line buffer (Double Buffered)
// Bank 0: Even Lines, Bank 1: Odd Lines
// Bits [4:0]: Pixel index (0-31)
// Bits [9:5]: Palette index (0-31)
reg [9:0] line_buffer [0:1][0:447]; 

wire        buf_wr = v_cnt[0];     // Write to current line index
wire        buf_rd = ~v_cnt[0];    // Read from previous line index
wire [10:0] cur_fetch_x = line_sprites[curr_sprite_idx].x + {1'b0, px_sub_cnt};

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
                if (active_sprites_count > 0 && curr_sprite_idx < active_sprites_count) begin
                    if (!ddram_busy) begin
                        // Unpacking 12 pixels from 64-bit SDRAM data (4 words x 3 pixels)
                        // Structure: [Word3][Word2][Word1][Word0]
                        // Each Word: [Ink:1][P2:5][P1:5][P0:5]
                        
                        // Note: cur_fetch_x is defined as a wire above
                        
                        if (cur_fetch_x < 448) begin
                            case (px_sub_cnt)
                                // Word 0
                                4'd0:  line_buffer[buf_wr][cur_fetch_x] <= {line_sprites[curr_sprite_idx].pal, ddram_dout[4:0]};
                                4'd1:  line_buffer[buf_wr][cur_fetch_x] <= {line_sprites[curr_sprite_idx].pal, ddram_dout[9:5]};
                                4'd2:  line_buffer[buf_wr][cur_fetch_x] <= {line_sprites[curr_sprite_idx].pal, ddram_dout[14:10]};
                                // Word 1
                                4'd3:  line_buffer[buf_wr][cur_fetch_x] <= {line_sprites[curr_sprite_idx].pal, ddram_dout[20:16]};
                                4'd4:  line_buffer[buf_wr][cur_fetch_x] <= {line_sprites[curr_sprite_idx].pal, ddram_dout[25:21]};
                                4'd5:  line_buffer[buf_wr][cur_fetch_x] <= {line_sprites[curr_sprite_idx].pal, ddram_dout[30:26]};
                                // Word 2
                                4'd6:  line_buffer[buf_wr][cur_fetch_x] <= {line_sprites[curr_sprite_idx].pal, ddram_dout[36:32]};
                                4'd7:  line_buffer[buf_wr][cur_fetch_x] <= {line_sprites[curr_sprite_idx].pal, ddram_dout[41:37]};
                                4'd8:  line_buffer[buf_wr][cur_fetch_x] <= {line_sprites[curr_sprite_idx].pal, ddram_dout[46:42]};
                                // Word 3
                                4'd9:  line_buffer[buf_wr][cur_fetch_x] <= {line_sprites[curr_sprite_idx].pal, ddram_dout[52:48]};
                                4'd10: line_buffer[buf_wr][cur_fetch_x] <= {line_sprites[curr_sprite_idx].pal, ddram_dout[57:53]};
                                4'd11: line_buffer[buf_wr][cur_fetch_x] <= {line_sprites[curr_sprite_idx].pal, ddram_dout[62:58]};
                            endcase
                        end

                        if (px_sub_cnt == 11) begin
                            px_sub_cnt <= 0;
                            curr_sprite_idx <= curr_sprite_idx + 1'd1;
                        end else begin
                            px_sub_cnt <= px_sub_cnt + 1'd1;
                        end
                        end
                    end // Close active_sprites logic
                
                // Transition Check (Now outside the active loop)
                if (curr_sprite_idx == active_sprites_count) begin
                    ddram_rd <= 0;
                    sprite_state <= WAIT_START;
                end
            end // Close FETCH_SPRITES state

            WAIT_START: begin
                // Wait for verify H-Blank start (approx line end) to begin scanning for NEXT line.
                // Current line is being displayed (reading from buf_rd).
                // We write to buf_wr.
                // Scan starts at 640.
                if (h_cnt == 640) begin
                    sprite_state <= SCAN_SPRITES;
                    // Prepare for next line
                    curr_sprite_idx <= 0;
                    active_sprites_count <= 0;
                    attr_cnt <= 0;
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
reg [9:0] sprite_data;
reg       is_sprite;

always @(posedge clk) begin
    if (!active) begin
        r <= 0; g <= 0; b <= 0;
        pal_addr <= 0;
        is_sprite <= 0;
    end else begin
        // Pipeline Stage 1: Address Setup
        // Priority: Sprite > BG
        // Note: line_buffer read is async or sync? Infer M10K -> sync.
        // But line_buffer is 'reg', so it's logic/registers (or simple RAM).
        // For 448 pixels, FPGA fits this in regs or MLAB.
        
        sprite_data = line_buffer[buf_rd][px];
        
        // Clear-on-Read (Clear the pixel we just read for the next frame use)
        // This avoids the 448-cycle CLEAR_BUFFER state.
        line_buffer[buf_rd][px] <= 10'd0;
        
        if (sprite_data[4:0] != 0) begin
            pal_addr <= {sprite_data[9:5], sprite_data[4:0]}; // Pal(5) + Color(5)
            is_sprite <= 1'b1;
        end else begin
            // BG Color (Need to implement BG Palette logic too!)
            // Use Dummy BG for now
            pal_addr <= {5'd0, 5'd0}; 
            is_sprite <= 1'b0;
        end
        
        // Pipeline Stage 2: Color Output (from pal_dout)
        // pal_dout is RGB555 (15 bits).
        // PGM Color format: XRRRRRGGGGGBBBBB
        
        if (is_sprite) begin
            r <= {pal_dout[14:10], 3'b0};
            g <= {pal_dout[9:5],   3'b0};
            b <= {pal_dout[4:0],   3'b0};
        end else begin
             // BG Placeholder (White for BG, Black for nothing)
             // Actually, use bg_data from tilemap
             r <= bg_data[15:11] << 3;
             g <= bg_data[10:5]  << 2;
             b <= bg_data[4:0]   << 3;
        end
    end
end

endmodule
