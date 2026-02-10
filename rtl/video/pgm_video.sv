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
reg [9:0]  h_cnt, v_cnt;
reg        hs_d1, vs_d1, blank_n_d1;

// Sprite Engine Regs
reg [1:0]  sprite_state;
reg [9:0]  px_sub_cnt;
reg [7:0]  curr_sprite_idx;
reg [5:0]  active_sprites_count; // Restaurado a 32 (5 bits + 1)
reg [2:0]  sprite_attr_cnt;

// Temp regs for scanning
reg [11:0] temp_sy;
reg [10:0] temp_sx;
reg [5:0]  temp_sh;
reg [15:0] temp_code;
reg        temp_flipx;
reg [15:0] x_accum_reg; // X Accumulator for Scaling
reg [5:0]  source_x_ptr;

struct packed {
    logic [10:0] x;
    logic [4:0]  pal;
    logic [15:0] code;
    logic [7:0]  x_zoom;
    logic [11:0] source_y_offset;
    logic        flipx;
} line_sprites [0:31]; // Restaurado a 32 sprites por línea

// --- Buffer RAM Instances ---
wire [9:0] lb0_rd, lb1_rd;
reg  lb0_we, lb1_we;
reg  [8:0] lb_wa;
reg  [9:0] lb_wd;

dpram #(9, 10) lb0_mem (.clk(clk), .we(lb0_we), .wa(lb_wa), .wd(lb_wd), .ra(px[8:0]), .rd(lb0_rd));
dpram #(9, 10) lb1_mem (.clk(clk), .we(lb1_we), .wa(lb_wa), .wd(lb_wd), .ra(px[8:0]), .rd(lb1_rd));

wire [9:0] tx_rd;
reg  tx_we;
reg  [8:0] tx_wa;
reg  [9:0] tx_wd;
dpram #(9, 10) tx_mem (.clk(clk), .we(tx_we), .wa(tx_wa), .wd(tx_wd), .ra(px[8:0]), .rd(tx_rd));

wire [4:0] bg_rd;
reg  bg_we;
reg  [8:0] bg_wa;
reg  [4:0] bg_wd;
dpram #(9, 5) bg_mem (.clk(clk), .we(bg_we), .wa(bg_wa), .wd(bg_wd), .ra(px[8:0]), .rd(bg_rd));

// Tile Engine Regs
reg [1:0]  tile_state;
reg [5:0]  tx_fetch_cnt; 
reg [15:0] tx_tile_idx, tx_tile_attr;
reg        tx_attr_phase;
reg [3:0]  tile_write_cnt; // Sequential write counter (0-7 or 0-9)

reg [4:0]  bg_fetch_cnt; 
reg [15:0] bg_tile_idx, bg_tile_attr;
reg        bg_attr_phase;
reg [1:0]  bg_sdram_phase;

// --- Continuous Assignments ---
wire [15:0] bg_scrolly = vregs[(16+2)*16 +: 16]; 
wire [15:0] bg_scrollx = vregs[(16+3)*16 +: 16]; 
wire [15:0] tx_scrolly = vregs[(16+5)*16 +: 16]; 
wire [15:0] tx_scrollx = vregs[(16+6)*16 +: 16]; 

wire [9:0] px = h_cnt - 10'd96;
wire [9:0] py = v_cnt - 10'd128;
wire       active = (h_cnt >= 96 && h_cnt < 544 && v_cnt >= 128 && v_cnt < 352);
wire       blank_n_w = active;

wire       buf_wr_idx = v_cnt[0];
wire       buf_rd_idx = ~v_cnt[0];

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
    hs <= hs_d1; vs <= vs_d1; blank_n <= blank_n_d1;
end

// --- SDRAM Bus Arbiter ---
always @(posedge clk) begin
    if (reset) begin
        ddram_rd <= 1'b0; ddram_addr <= 0;
    end else begin
        if (sprite_state == FETCH_SPRITES && active_sprites_count > 0 && curr_sprite_idx < active_sprites_count) begin
            if (!ddram_busy && !ddram_rd) begin
                ddram_rd <= 1'b1;
                ddram_addr <= {5'd0, line_sprites[curr_sprite_idx].code, 3'd0} + 
                              {12'd0, line_sprites[curr_sprite_idx].source_y_offset, 5'd0} + 
                              {25'd0, source_x_ptr[5:4]};
            end else if (ddram_dout_ready) ddram_rd <= 1'b0;
        end else if (tile_state == TILE_SDRAM && tile_write_cnt == 0) begin
            if (!ddram_busy && !ddram_rd) begin
                ddram_rd <= 1'b1;
                if (tx_fetch_cnt < 56) 
                    ddram_addr <= {7'd0, tx_tile_idx[11:0], 5'd0} + {24'd0, tx_tile_line[2:1], 3'd0}; 
                else 
                    ddram_addr <= {2'd1, bg_tile_idx[11:0], 15'd0} + {bg_tile_line, bg_sdram_phase};
            end else if (ddram_dout_ready) ddram_rd <= 1'b0;
        end else ddram_rd <= 1'b0;
    end
end

// --- Sprite Engine & Buffer Control ---
always @(posedge clk) begin
    if (reset) begin
        sprite_state <= SCAN_SPRITES;
        curr_sprite_idx <= 0; active_sprites_count <= 0; sprite_attr_cnt <= 0;
        source_x_ptr <= 0; px_sub_cnt <= 0;
        lb0_we <= 0; lb1_we <= 0; lb_wa <= 0; lb_wd <= 0;
    end else begin
        // Sequential Clear logic
        if (h_cnt < 512) begin
            lb_wa <= h_cnt[8:0]; lb_wd <= 0;
            if (buf_wr_idx == 0) begin lb0_we <= 1; lb1_we <= 0; end
            else begin lb1_we <= 1; lb0_we <= 0; end
        end else begin
            lb0_we <= 0; lb1_we <= 0;
            
            case (sprite_state)
                SCAN_SPRITES: begin
                    if (h_cnt >= 640) begin
                        sprite_addr <= {curr_sprite_idx, 2'b00} + sprite_attr_cnt[1:0];
                        case (sprite_attr_cnt)
                            3'd0: temp_sy <= sprite_dout[11:0];
                            3'd1: temp_sx <= sprite_dout[10:0];
                            3'd2: begin temp_sh <= sprite_dout[5:0]; temp_flipx <= sprite_dout[6]; end
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
                                            line_sprites[active_sprites_count].source_y_offset <= sy_off[11:0];
                                            line_sprites[active_sprites_count].pal <= sprite_dout[13:9];
                                            line_sprites[active_sprites_count].flipx <= temp_flipx;
                                            active_sprites_count <= active_sprites_count + 1'd1;
                                        end
                                    end
                                end
                            end
                        endcase
                        if (sprite_attr_cnt == 4) begin
                            sprite_attr_cnt <= 0; curr_sprite_idx <= curr_sprite_idx + 1'd1;
                            if (curr_sprite_idx == 255) sprite_state <= FETCH_SPRITES;
                        end else sprite_attr_cnt <= sprite_attr_cnt + 1'd1;
                    end
                end
                
                FETCH_SPRITES: begin
                    if (active_sprites_count > 0 && curr_sprite_idx < active_sprites_count) begin
                        if (ddram_dout_ready) begin
                            // Sequential write to RAM (no more loop!)
                            // We write 1 pixel per clock cycle here for simplicity and safety
                            automatic int dx = line_sprites[curr_sprite_idx].x + px_sub_cnt;
                            if (dx < 448) begin
                                lb_wa <= dx[8:0]; lb_wd <= {line_sprites[curr_sprite_idx].pal, ddram_dout[px_sub_cnt*5 +: 5]};
                                if (buf_wr_idx == 0) begin lb0_we <= 1; lb1_we <= 0; end
                                else begin lb1_we <= 1; lb0_we <= 0; end
                            end
                            if (px_sub_cnt == 11) begin
                                px_sub_cnt <= 0; 
                                source_x_ptr <= source_x_ptr + 6'd12;
                                if (source_x_ptr >= 48) begin
                                    source_x_ptr <= 0; curr_sprite_idx <= curr_sprite_idx + 1'd1;
                                end
                            end else px_sub_cnt <= px_sub_cnt + 1'd1;
                        end else begin lb0_we <= 0; lb1_we <= 0; end
                    end else begin lb0_we <= 0; lb1_we <= 0; end
                    if (curr_sprite_idx == active_sprites_count) sprite_state <= WAIT_START;
                end

                WAIT_START: begin
                    lb0_we <= 0; lb1_we <= 0;
                    if (h_cnt == 640) begin
                        sprite_state <= SCAN_SPRITES; curr_sprite_idx <= 0; active_sprites_count <= 0; sprite_attr_cnt <= 0;
                    end
                end
            endcase
        end
    end
end

// --- Tile Engine ---
always @(posedge clk) begin
    if (reset) begin
        tile_state <= TILE_IDLE; tx_fetch_cnt <= 0; bg_fetch_cnt <= 0;
        tx_attr_phase <= 0; bg_attr_phase <= 0; bg_sdram_phase <= 0;
        tx_we <= 0; bg_we <= 0; tile_write_cnt <= 0;
    end else begin
        case (tile_state)
            TILE_IDLE: if (h_cnt == 0) begin tile_state <= TILE_VRAM; tx_fetch_cnt <= 0; bg_fetch_cnt <= 0; end
            TILE_VRAM: begin
                tx_we <= 0; bg_we <= 0; tile_write_cnt <= 0;
                if (tx_fetch_cnt < 56) begin
                    vram_addr <= 14'h2000 + (((tx_vram_row * 64) + ((tx_fetch_cnt + tx_scrollx[8:3]) & 6'h3F)) << 1) + {13'd0, tx_attr_phase};
                    if (tx_attr_phase == 0) begin tx_tile_idx <= vram_dout; tx_attr_phase <= 1; end
                    else begin tx_tile_attr <= vram_dout; tx_attr_phase <= 0; tile_state <= TILE_SDRAM; end
                end else if (bg_fetch_cnt < 15) begin
                    vram_addr <= 14'h0000 + (((bg_vram_row * 64) + ((bg_fetch_cnt + bg_scrollx[9:5]) & 6'h3F)) << 1) + {13'd0, bg_attr_phase};
                    if (bg_attr_phase == 0) begin bg_tile_idx <= vram_dout; bg_attr_phase <= 1; end
                    else begin bg_tile_attr <= vram_dout; bg_attr_phase <= 0; tile_state <= TILE_SDRAM; bg_sdram_phase <= 0; end
                end else tile_state <= TILE_IDLE;
            end
            TILE_SDRAM: if (ddram_dout_ready || tile_write_cnt > 0) begin
                if (tx_fetch_cnt < 56) begin
                    // Sequential write to RAM (8 pixels)
                    tx_we <= 1; tx_wa <= (tx_fetch_cnt*8 + tile_write_cnt);
                    tx_wd <= {tx_tile_attr[5:1], (tx_tile_line[0] ? ddram_dout[32 + tile_write_cnt*4 +: 4] : ddram_dout[tile_write_cnt*4 +: 4])};
                    if (tile_write_cnt == 7) begin
                        tx_fetch_cnt <= tx_fetch_cnt + 1'd1; tile_state <= TILE_VRAM;
                    end else tile_write_cnt <= tile_write_cnt + 1'd1;
                end else begin
                    // Sequential write to BG RAM (10 pixels per SDRAM read)
                    bg_we <= 1; bg_wa <= (bg_fetch_cnt*32 + bg_sdram_phase*10 + tile_write_cnt);
                    bg_wd <= ddram_dout[tile_write_cnt*5 +: 5];
                    if (tile_write_cnt == 9) begin
                        if (bg_sdram_phase == 2) begin
                            bg_sdram_phase <= 0; bg_fetch_cnt <= bg_fetch_cnt + 1'd1; tile_state <= TILE_VRAM;
                        end else begin bg_sdram_phase <= bg_sdram_phase + 1'd1; tile_state <= TILE_VRAM; end // Go fetch next 10 px
                    end else tile_write_cnt <= tile_write_cnt + 1'd1;
                end
            end
        endcase
    end
end

// --- Mixer ---
always @(posedge clk) begin
    if (!blank_n_w) begin
        r <= 0; g <= 0; b <= 0; pal_addr <= 0;
    end else begin
        automatic logic [9:0] s_data = (buf_rd_idx == 0) ? lb0_rd : lb1_rd;
        automatic logic [9:0] t_p    = tx_rd;
        automatic logic [4:0] b_p    = bg_rd;
        if (t_p[3:0] != 15) pal_addr <= {5'd1, t_p[4:0]}; 
        else if (s_data[4:0] != 0) pal_addr <= {s_data[9:5], s_data[4:0]}; 
        else pal_addr <= {5'd2, b_p}; 
        if (t_p[3:0] != 15 || s_data[4:0] != 0 || b_p != 0) begin
            r <= {pal_dout[14:10], 3'b0}; g <= {pal_dout[9:5], 3'b0}; b <= {pal_dout[4:0], 3'b0};
        end else begin r <= 0; g <= 32; b <= 32; end
    end
end

endmodule
