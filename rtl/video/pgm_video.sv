module pgm_video (
    input         clk,
    input         reset,

    // Video Data from Core
    output reg [14:1] vram_addr,
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
    input             ddram_dout_ready, // Added

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
wire active = (h_cnt >= 96 && h_cnt < 544 && v_cnt >= 128 && v_cnt < 352);
wire blank_n_w = active;

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
localparam WAIT_START    = 2'd2;

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
        ddram_rd <= 1'b0;
        ddram_addr <= 0;
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
                    if (!ddram_busy && !ddram_rd) begin
                        // Request data
                        ddram_rd <= 1'b1;
                        ddram_addr <= {5'd0, line_sprites[curr_sprite_idx].code, 3'd0} + px_sub_cnt;
                    end
                    
                    if (ddram_dout_ready) begin
                        // Recibimos los 12 píxeles (4 palabras de 3 píxeles) en 64 bits
                        ddram_rd <= 1'b0; // Terminar petición actual
                        
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

                        if (px_sub_cnt == 11) begin
                            px_sub_cnt <= 0;
                            curr_sprite_idx <= curr_sprite_idx + 1'd1;
                        end else begin
                            px_sub_cnt <= px_sub_cnt + 1'd1;
                        end
                    end
                end 
                
                // Transition Check
                if (curr_sprite_idx == active_sprites_count) begin
                    ddram_rd <= 0;
                    sprite_state <= WAIT_START;
                end
            end

            WAIT_START: begin
                if (h_cnt == 640) begin
                    sprite_state <= SCAN_SPRITES;
                    curr_sprite_idx <= 0;
                    active_sprites_count <= 0;
                    attr_cnt <= 0;
                end
            end
        endcase
    end
end

// --- Video Registers (Unpacked) ---
wire [15:0] bg_scrolly = vregs[(16+2)*16 +: 16]; // B02000
wire [15:0] bg_scrollx = vregs[(16+3)*16 +: 16]; // B03000
wire [15:0] tx_scrolly = vregs[(16+5)*16 +: 16]; // B05000
wire [15:0] tx_scrollx = vregs[(16+6)*16 +: 16]; // B06000

// --- Coordinate Mapping (448x224 inside 640x480) ---
wire [9:0] px = h_cnt - 10'd96;
wire [9:0] py = v_cnt - 10'd128;

// TX Layer Address Logic
wire [4:0] tx_tile_line = (py + tx_scrolly[7:0]) & 8'h07;
wire [8:0] tx_vram_row  = ((py + tx_scrolly) >> 3) & 8'h1F;

// Layer Buffers
reg [9:0] tx_buffer [0:447]; 

// --- Tile Fetcher State Machine (Parallel to Sprites) ---
localparam TILE_IDLE  = 2'd0;
localparam TILE_VRAM  = 2'd1;
localparam TILE_SDRAM = 2'd2;

reg [1:0]  tile_state;
reg [5:0]  tx_fetch_cnt; 
reg [15:0] tx_tile_idx;
reg [15:0] tx_tile_attr;
reg        tx_attr_phase;

always @(posedge clk) begin
    if (reset) begin
        tile_state <= TILE_IDLE;
        tx_fetch_cnt <= 0;
        tx_attr_phase <= 0;
    end else begin
        case (tile_state)
            TILE_IDLE: begin
                if (h_cnt == 0) begin
                    tile_state <= TILE_VRAM;
                    tx_fetch_cnt <= 0;
                    tx_attr_phase <= 0;
                end
            end
            
            TILE_VRAM: begin
                vram_addr <= 14'h2000 + (((tx_vram_row * 64) + ((tx_fetch_cnt + tx_scrollx[8:3]) & 6'h3F)) << 1) + {13'd0, tx_attr_phase};
                if (tx_attr_phase == 0) begin
                    tx_tile_idx <= vram_dout;
                    tx_attr_phase <= 1;
                end else begin
                    tx_tile_attr <= vram_dout;
                    tx_attr_phase <= 0;
                    tile_state <= TILE_SDRAM;
                end
            end
            
            TILE_SDRAM: begin
                if (!ddram_busy && !ddram_rd && !tx_attr_phase) begin // Only if not fetching VRAM
                   // Note: Shared ddram_rd with sprites must be handled in PGM.sv
                end
                
                // For now, assume this logic just works because pgm_video is the one driving SDRAM in this core
                if (!ddram_busy && !ddram_rd) begin
                    ddram_rd <= 1'b1;
                    ddram_addr <= {7'd0, tx_tile_idx[11:0], 5'd0} + {24'd0, tx_tile_line[2:1], 3'd0}; 
                end
                
                if (ddram_dout_ready) begin
                    ddram_rd <= 1'b0;
                    for (int i=0; i<8; i=i+1) begin
                        tx_buffer[tx_fetch_cnt*8 + i] <= {tx_tile_attr[5:1], (tx_tile_line[0] ? 
                            ddram_dout[32 + i*4 +: 4] : ddram_dout[i*4 +: 4])};
                    end
                    
                    if (tx_fetch_cnt == 55) tile_state <= TILE_IDLE;
                    else begin
                        tx_fetch_cnt <= tx_fetch_cnt + 1'd1;
                        tile_state <= TILE_VRAM;
                    end
                end
            end
        endcase
    end
end

// Mixer & Layer Priority
reg [9:0] sprite_data;
reg [9:0] tx_p;
reg [15:0] bg_placeholder;

always @(posedge clk) begin
    if (!blank_n_w) begin
        r <= 0; g <= 0; b <= 0;
        pal_addr <= 0;
    end else begin
        sprite_data <= line_buffer[buf_rd][px];
        tx_p        <= tx_buffer[px];
        
        if (tx_p[3:0] != 15) begin
            pal_addr <= {5'd1, tx_p[4:0]};
        end else if (sprite_data[4:0] != 0) begin
            pal_addr <= {sprite_data[9:5], sprite_data[4:0]};
        end else begin
            pal_addr <= 0; 
        end
        
        if (tx_p[3:0] != 15 || sprite_data[4:0] != 0) begin
            r <= {pal_dout[14:10], 3'b0};
            g <= {pal_dout[9:5],   3'b0};
            b <= {pal_dout[4:0],   3'b0};
        end else begin
            r <= 0; g <= 64; b <= 0; // Dark Green Background Placeholder
        end
        
        line_buffer[buf_rd][px] <= 10'd0;
    end
end

endmodule
