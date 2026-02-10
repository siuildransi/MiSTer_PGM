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
    input             ddram_dout_ready, 

    // Video Output
    output reg        hs,
    output reg        vs,
    output reg [7:0]  r,
    output reg [7:0]  g,
    output reg [7:0]  b,
    output reg        blank_n
);

// --- Constants ---
localparam SCAN_SPRITES  = 2'd0;
localparam FETCH_SPRITES = 2'd1;
localparam WAIT_START    = 2'd2;

localparam TILE_IDLE  = 2'd0;
localparam TILE_VRAM  = 2'd1;
localparam TILE_SDRAM = 2'd2;

// --- Registers and Internal Signals ---
reg [9:0]  h_cnt;
reg [9:0]  v_cnt;
reg        hs_d1, vs_d1, blank_n_d1;

// Sprite Engine Regs
reg [1:0]  sprite_state;
reg [9:0]  px_sub_cnt;
reg [7:0]  curr_sprite_idx;
reg [7:0]  active_sprites_count;
reg [2:0]  sprite_attr_cnt;

// Temp regs for scanning (Fase C)
reg [11:0] temp_sy;
reg [10:0] temp_sx;
reg [5:0]  temp_sh;
reg [15:0] temp_code;
reg        temp_flipx, temp_flipy;
reg [15:0] x_accum;
reg [5:0]  source_x_ptr;

struct packed {
    logic [10:0] x;
    logic [4:0]  pal;
    logic [15:0] code;
    logic [7:0]  x_zoom;
    logic [11:0] source_y_offset; // Which row to fetch from SDRAM
    logic [4:0]  width;          // Width in 16-pixel units (approx)
    logic        flipx;
} line_sprites [0:31];

reg [9:0] line_buffer [0:1][0:447]; 

// Tile Engine Regs
reg [1:0]  tile_state;
localparam TILE_FETCH_TX = 2'd1;
localparam TILE_FETCH_BG = 2'd2;

reg [5:0]  tx_fetch_cnt; 
reg [15:0] tx_tile_idx;
reg [15:0] tx_tile_attr;
reg        tx_attr_phase;
reg [9:0]  tx_buffer [0:447]; 

reg [4:0]  bg_fetch_cnt; // 0-14 tiles
reg [15:0] bg_tile_idx;
reg [15:0] bg_tile_attr;
reg        bg_attr_phase;
reg [1:0]  bg_sdram_phase;
reg [4:0]  bg_buffer [0:447]; // BG Pixel buffer (5bpp)

// --- Continuous Assignments (Muxes & Math) ---
wire [15:0] bg_scrolly = vregs[(16+2)*16 +: 16]; // B02000
wire [15:0] bg_scrollx = vregs[(16+3)*16 +: 16]; // B03000
wire [15:0] tx_scrolly = vregs[(16+5)*16 +: 16]; // B05000
wire [15:0] tx_scrollx = vregs[(16+6)*16 +: 16]; // B06000

wire [9:0] px = h_cnt - 10'd96;
wire [9:0] py = v_cnt - 10'd128;
wire       active = (h_cnt >= 96 && h_cnt < 544 && v_cnt >= 128 && v_cnt < 352);
wire       blank_n_w = active;

wire        buf_wr = v_cnt[0];
wire        buf_rd = ~v_cnt[0];

wire [4:0] tx_tile_line = (py + tx_scrolly[7:0]) & 8'h07;
wire [8:0] tx_vram_row  = ((py + tx_scrolly) >> 3) & 8'h1F;

wire [4:0] bg_tile_line = (py + bg_scrolly[7:0]) & 8'h1F;
wire [8:0] bg_vram_row  = ((py + bg_scrolly) >> 5) & 8'h0F;

// --- Timing Generator ---
always @(posedge clk) begin
    if (reset) begin
        h_cnt <= 0; v_cnt <= 0;
    end else begin
        if (h_cnt == 799) begin
            h_cnt <= 0;
            if (v_cnt == 524) v_cnt <= 0;
            else v_cnt <= v_cnt + 1'd1;
        end else h_cnt <= h_cnt + 1'd1;
    end
end

always @(posedge clk) begin
    hs_d1 <= ~(h_cnt >= 656 && h_cnt < 752);
    vs_d1 <= ~(v_cnt >= 490 && v_cnt < 492);
    blank_n_d1 <= blank_n_w;
    
    hs <= hs_d1;
    vs <= vs_d1;
    blank_n <= blank_n_d1;
end

// --- SDRAM Bus Arbiter ---
always @(posedge clk) begin
    if (reset) begin
        ddram_rd <= 1'b0;
        ddram_addr <= 0;
    end else begin
        if (sprite_state == FETCH_SPRITES && active_sprites_count > 0 && curr_sprite_idx < active_sprites_count) begin
            // Sprite priority
            if (!ddram_busy && !ddram_rd) begin
                ddram_rd <= 1'b1;
                // Address calculation with vertical offset
                ddram_addr <= {5'd0, line_sprites[curr_sprite_idx].code, 3'd0} + 
                              {12'd0, line_sprites[curr_sprite_idx].source_y_offset, 5'd0} + 
                              {25'd0, source_x_ptr[5:4]};
            end else if (ddram_dout_ready) begin
                ddram_rd <= 1'b0;
            end
        end else if (tile_state == TILE_SDRAM) begin
            // TX/BG priority
            if (!ddram_busy && !ddram_rd) begin
                ddram_rd <= 1'b1;
                if (tx_fetch_cnt < 56) begin
                    ddram_addr <= {7'd0, tx_tile_idx[11:0], 5'd0} + {24'd0, tx_tile_line[2:1], 3'd0}; 
                end else begin
                    ddram_addr <= {2'd1, bg_tile_idx[11:0], 15'd0} + {bg_tile_line, bg_sdram_phase};
                end
            end else if (ddram_dout_ready) begin
                ddram_rd <= 1'b0;
            end
        end else begin
            ddram_rd <= 1'b0;
        end
    end
end

// --- Sprite Engine State Machine ---
always @(posedge clk) begin
    if (reset) begin
        sprite_state <= SCAN_SPRITES;
        curr_sprite_idx <= 0;
        active_sprites_count <= 0;
        sprite_attr_cnt <= 0;
        x_accum <= 0;
        source_x_ptr <= 0;
    end else begin
        case (sprite_state)
            SCAN_SPRITES: begin
                if (h_cnt >= 640) begin
                    sprite_addr <= {curr_sprite_idx, 2'b00} + sprite_attr_cnt[1:0];
                    case (sprite_attr_cnt)
                        3'd0: temp_sy <= sprite_dout[11:0];
                        3'd1: temp_sx <= sprite_dout[10:0];
                        3'd2: begin
                            temp_sh <= sprite_dout[5:0];
                            temp_flipy <= sprite_dout[7];
                            temp_flipx <= sprite_dout[6];
                        end
                        3'd3: temp_code <= sprite_dout;
                        3'd4: begin
                            automatic int zx = (sprite_dout[7:0] == 0)  ? 64 : sprite_dout[7:0];
                            automatic int zy = (sprite_dout[15:8] == 0) ? 64 : sprite_dout[15:8];
                            
                            if (v_cnt >= temp_sy) begin
                                automatic int dy = v_cnt - temp_sy;
                                automatic int sy_off = (dy * zy) >> 6;
                                
                                if (sy_off < temp_sh) begin
                                    if (active_sprites_count < 32) begin
                                        line_sprites[active_sprites_count].x <= temp_sx;
                                        line_sprites[active_sprites_count].code <= temp_code;
                                        line_sprites[active_sprites_count].x_zoom <= zx;
                                        line_sprites[active_sprites_count].source_y_offset <= sy_off;
                                        line_sprites[active_sprites_count].pal <= sprite_dout[13:9];
                                        line_sprites[active_sprites_count].width <= 4;
                                        line_sprites[active_sprites_count].flipx <= temp_flipx;
                                        active_sprites_count <= active_sprites_count + 1'd1;
                                    end
                                end
                            end
                        end
                    endcase
                    
                    if (sprite_attr_cnt == 4) begin
                        sprite_attr_cnt <= 0;
                        curr_sprite_idx <= curr_sprite_idx + 1'd1;
                        if (curr_sprite_idx == 255) sprite_state <= FETCH_SPRITES;
                    end else sprite_attr_cnt <= sprite_attr_cnt + 1'd1;
                end
            end
            
            FETCH_SPRITES: begin
                if (active_sprites_count > 0 && curr_sprite_idx < active_sprites_count) begin
                    if (ddram_dout_ready) begin
                        for (int i=0; i<12; i=i+1) begin
                            automatic int dx = line_sprites[curr_sprite_idx].x + px_sub_cnt;
                            if (dx < 448) begin
                                line_buffer[buf_wr][dx] <= {line_sprites[curr_sprite_idx].pal, ddram_dout[i*5 +: 5]};
                            end
                            px_sub_cnt <= px_sub_cnt + 1'd1;
                        end
                        
                        source_x_ptr <= source_x_ptr + 6'd12;
                        if (source_x_ptr >= 48) begin
                            source_x_ptr <= 0;
                            px_sub_cnt <= 0;
                            curr_sprite_idx <= curr_sprite_idx + 1'd1;
                        end
                    end
                end 
                if (curr_sprite_idx == active_sprites_count) sprite_state <= WAIT_START;
            end

            WAIT_START: begin
                if (h_cnt == 640) begin
                    sprite_state <= SCAN_SPRITES;
                    curr_sprite_idx <= 0;
                    active_sprites_count <= 0;
                    sprite_attr_cnt <= 0;
                end
            end
        endcase
    end
end

// --- Tile Engine State Machine ---
always @(posedge clk) begin
    if (reset) begin
        tile_state <= TILE_IDLE;
        tx_fetch_cnt <= 0;
        bg_fetch_cnt <= 0;
        tx_attr_phase <= 0;
        bg_attr_phase <= 0;
        bg_sdram_phase <= 0;
    end else begin
        case (tile_state)
            TILE_IDLE: begin
                if (h_cnt == 0) begin
                    tile_state <= TILE_VRAM;
                    tx_fetch_cnt <= 0;
                    bg_fetch_cnt <= 0;
                end
            end
            
            TILE_VRAM: begin
                if (tx_fetch_cnt < 56) begin
                    vram_addr <= 14'h2000 + (((tx_vram_row * 64) + ((tx_fetch_cnt + tx_scrollx[8:3]) & 6'h3F)) << 1) + {13'd0, tx_attr_phase};
                    if (tx_attr_phase == 0) begin tx_tile_idx <= vram_dout; tx_attr_phase <= 1; end
                    else begin tx_tile_attr <= vram_dout; tx_attr_phase <= 0; tile_state <= TILE_SDRAM; end
                end else if (bg_fetch_cnt < 15) begin
                    vram_addr <= 14'h0000 + (((bg_vram_row * 64) + ((bg_fetch_cnt + bg_scrollx[9:5]) & 6'h3F)) << 1) + {13'd0, bg_attr_phase};
                    if (bg_attr_phase == 0) begin bg_tile_idx <= vram_dout; bg_attr_phase <= 1; end
                    else begin bg_tile_attr <= vram_dout; bg_attr_phase <= 0; tile_state <= TILE_SDRAM; bg_sdram_phase <= 0; end
                end else begin
                    tile_state <= TILE_IDLE;
                end
            end
            
            TILE_SDRAM: begin
                if (ddram_dout_ready) begin
                    if (tx_fetch_cnt < 56) begin
                        for (int i=0; i<8; i=i+1) begin
                            tx_buffer[tx_fetch_cnt*8 + i] <= {tx_tile_attr[5:1], (tx_tile_line[0] ? ddram_dout[32 + i*4 +: 4] : ddram_dout[i*4 +: 4])};
                        end
                        tx_fetch_cnt <= tx_fetch_cnt + 1'd1;
                        tile_state <= TILE_VRAM;
                    end else begin
                        for (int i=0; i<10; i=i+1) begin
                             if ((bg_fetch_cnt*32 + bg_sdram_phase*10 + i) < 448)
                                bg_buffer[bg_fetch_cnt*32 + bg_sdram_phase*10 + i] <= ddram_dout[i*5 +: 5];
                        end
                        if (bg_sdram_phase == 2) begin
                            bg_sdram_phase <= 0;
                            bg_fetch_cnt <= bg_fetch_cnt + 1'd1;
                            tile_state <= TILE_VRAM;
                        end else bg_sdram_phase <= bg_sdram_phase + 1'd1;
                    end
                end
            end
        endcase
    end
end

// --- Mixer & Layer Priority ---
reg [9:0] sprite_data;
reg [9:0] tx_p;
reg [4:0] bg_p;

always @(posedge clk) begin
    if (!blank_n_w) begin
        r <= 0; g <= 0; b <= 0;
        pal_addr <= 0;
    end else begin
        sprite_data <= line_buffer[buf_rd][px];
        tx_p        <= tx_buffer[px];
        bg_p        <= bg_buffer[px];
        
        if (tx_p[3:0] != 15) begin
            pal_addr <= {5'd1, tx_p[4:0]}; 
        end else if (sprite_data[4:0] != 0) begin
            pal_addr <= {sprite_data[9:5], sprite_data[4:0]}; 
        end else begin
            pal_addr <= {5'd2, bg_p}; 
        end
        
        if (tx_p[3:0] != 15 || sprite_data[4:0] != 0 || bg_p != 0) begin
            r <= {pal_dout[14:10], 3'b0};
            g <= {pal_dout[9:5],   3'b0};
            b <= {pal_dout[4:0],   3'b0};
        end else begin
            r <= 0; g <= 32; b <= 32; 
        end
        
        line_buffer[buf_rd][px] <= 10'd0;
    end
end

endmodule
