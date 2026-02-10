module PGM (
    // Clocks
    input         fixed_20m_clk,
    input         fixed_8m_clk,
    input         fixed_50m_clk,  // Added for SDRAM
    input         video_clk,     // ~25 MHz for Video Timing
    input         reset,

    // MiSTer ioctl interface
    input         ioctl_download,
    input         ioctl_wr,
    input  [26:0] ioctl_addr,
    input  [15:0] ioctl_dout,
    input  [7:0]  ioctl_index,

    // DDRAM Interface (Shared by Video and Loader)
    output        ddram_rd,
    output        ddram_we,       // Added
    output [28:0] ddram_addr,
    output [63:0] ddram_din,      // Added
    output [7:0]  ddram_be,       // Added
    input  [63:0] ddram_dout,
    input         ddram_busy,
    input         ddram_dout_ready, // Added

    // Audio Outputs
    output [15:0] sample_l,
    output [15:0] sample_r,

    // Video Outputs
    output [7:0]  v_r,
    output [7:0]  v_g,
    output [7:0]  v_b,
    output        v_hs,
    output        v_vs,
    output        v_blank
);

// --- 68000 Main CPU (fx68k) ---
wire [23:1] adr;
wire [15:0] d_out;
wire as_n, uds_n, lds_n, rw_n;
reg [15:0] cpu68k_din;
reg cpu68k_dtack_n;

// Main Work RAM (128KB = 64K words)
(* ramstyle = "no_rw_check" *) reg [7:0] wram_hi [0:65535];
(* ramstyle = "no_rw_check" *) reg [7:0] wram_lo [0:65535];

// Memory Decoding (PGM Map)
wire bios_sel  = (adr[23:20] == 4'h0);      // 000000 - 0FFFFF (BIOS en SDRAM)
wire prom_sel  = (adr[23:20] >= 4'h1 && adr[23:20] <= 4'h3); // 100000 - 3FFFFF (P-ROM en SDRAM)
wire ram_sel   = (adr[23:17] == 7'b1000000); // 800000 - 81FFFF (Work RAM)
wire vram_sel  = (adr[23:17] == 7'b1001000); // 900000 - 907FFF (VRAM)
wire pal_sel   = (adr[23:17] == 7'b1010000); // A00000 - A011FF (Palette)
wire vreg_sel  = (adr[23:16] == 8'hB0);      // B00000 - B0FFFF (Registers)

// Work RAM access (Synchronous)
reg [7:0] wram_rd_h, wram_rd_l;
always @(posedge fixed_20m_clk) begin
    if (ram_sel && !rw_n && !as_n) begin
        if (!uds_n) wram_hi[adr[16:1]] <= d_out[15:8];
        if (!lds_n) wram_lo[adr[16:1]] <= d_out[7:0];
    end
    wram_rd_h <= wram_hi[adr[16:1]];
    wram_rd_l <= wram_lo[adr[16:1]];
end

// SDRAM Interface & DTACK Logic
reg  sdram_req;
wire sdram_ack;
wire [15:0] sdram_data;

always @(*) begin
    cpu68k_dtack_n = 1'b1;
    cpu68k_din = 16'hFFFF;
    sdram_req = 1'b0;

    if (!as_n) begin
        if (ram_sel) begin
            cpu68k_dtack_n = 1'b0;
            cpu68k_din = {wram_rd_h, wram_rd_l};
        end else if (bios_sel || prom_sel) begin
            sdram_req = 1'b1;
            cpu68k_din = sdram_data;
            if (sdram_ack) cpu68k_dtack_n = 1'b0;
        end else if (pal_sel || vram_sel) begin
            // Paleta y VRAM en este core son BRAM instantánea
            cpu68k_dtack_n = 1'b0;
            // Din se maneja abajo en mux de lectura
        end
    end
end

fx68k main_cpu (
    .clk(fixed_20m_clk),
    .HALTn(1'b1),
    .extReset(reset),
    .pwrUp(reset),
    .enPhi1(1'b1),
    .enPhi2(1'b1),
    .eab(adr),
    .iEdb(cpu68k_din),
    .oEdb(d_out),
    .ASn(as_n),
    .UDSn(uds_n),
    .LDSn(lds_n),
    .eRWn(rw_n),
    .DTACKn(cpu68k_dtack_n),
    .IPL0n(1'b1),
    .IPL1n(1'b1),
    .IPL2n(1'b1),
    .VPAn(1'b1),
    .BRn(1'b1),
    .BGACKn(1'b1),
    .BERRn(1'b1)
);

// --- Z80 Sound CPU ---
wire [15:0] z_adr;
wire [7:0]  z_dout;
wire z_mreq_n, z_iorq_n, z_rd_n, z_wr_n;

// Tiny Z80 RAM (256 bytes)
(* ramstyle = "no_rw_check" *) reg [7:0] sound_ram [0:255];
reg [7:0] sram_rd;

always @(posedge fixed_8m_clk) begin
    if (!z_mreq_n && !z_wr_n)
        sound_ram[z_adr[7:0]] <= z_dout;
    sram_rd <= sound_ram[z_adr[7:0]];
end

T80s sound_cpu (
    .RESET_n(~reset),
    .CLK(fixed_8m_clk),
    .WAIT_n(1'b1),
    .INT_n(1'b1),
    .NMI_n(1'b1),
    .BUSRQ_n(1'b1),
    .A(z_adr),
    .DI(sram_rd),
    .DO(z_dout),
    .MREQ_n(z_mreq_n),
    .IORQ_n(z_iorq_n),
    .RD_n(z_rd_n),
    .WR_n(z_wr_n)
);

assign sample_l = 16'h0000;
assign sample_r = 16'h0000;

// --- Video System ---

// Video RAMs (Infer as M10K)
(* ramstyle = "no_rw_check" *) reg [15:0] pal_ram [0:2047]; // 4KB Palette
(* ramstyle = "no_rw_check" *) reg [15:0] vram    [0:16383]; // 32KB VRAM

// Zoom Table / Video Regs
reg [15:0] zoom_table [0:15];
reg [15:0] vid_regs   [0:15];

wire [511:0] vregs_packed;
genvar i;
generate
    for (i=0; i<16; i=i+1) begin : pack_zoom
        assign vregs_packed[i*16 +: 16] = zoom_table[i];
    end
    for (i=0; i<16; i=i+1) begin : pack_regs
        assign vregs_packed[(16+i)*16 +: 16] = vid_regs[i];
    end
endgenerate

// Connections
wire [14:1] vram_addr_vid;
wire [15:0] vram_dout_vid = vram[vram_addr_vid];

wire [12:1] pal_addr_vid;
wire [15:0] pal_dout_vid = pal_ram[pal_addr_vid[11:1]];

wire [10:1] spr_addr_vid;
// Sprite data comes from Main Work RAM (High/Low split in PGM.sv)
// We need to fetch 16-bit words from wram_hi/lo using spr_addr_vid
wire [15:0] spr_dout_vid = {wram_hi[spr_addr_vid[8:1]], wram_lo[spr_addr_vid[8:1]]}; 
// Note: spr_addr_vid is 10 bits (word address), wram is 256 words deep in this skeleton? 
// Current skeleton wram is too small (256 bytes). 
// Accessing index [8:1] (8 bits) is OK for 256 size.

// --- SDRAM Arbitrator (50MHz Domain) ---

// Sync CPU Request to 50MHz
reg  sdram_req_s1, sdram_req_s2;
always @(posedge fixed_50m_clk) {sdram_req_s2, sdram_req_s1} <= {sdram_req_s1, sdram_req};

// Sync Video Request to 50MHz
reg  vid_rd_s1, vid_rd_s2;
always @(posedge fixed_50m_clk) {vid_rd_s2, vid_rd_s1} <= {vid_rd_s1, vid_rd};

reg [1:0] arb_state;
localparam ARB_IDLE   = 2'd0;
localparam ARB_CPU    = 2'd1;
localparam ARB_VIDEO  = 2'd2;

reg        sdram_ack_50;
reg        vid_ack_50;
reg [63:0] sdram_buf;

assign sdram_data = (adr[2:1] == 2'd0) ? sdram_buf[15:0]  :
                    (adr[2:1] == 2'd1) ? sdram_buf[31:16] :
                    (adr[2:1] == 2'd2) ? sdram_buf[47:32] : sdram_buf[63:48];

// Sync Ack back to 20MHz
reg  sdram_ack_s1, sdram_ack_s2;
always @(posedge fixed_20m_clk) {sdram_ack_s2, sdram_ack_s1} <= {sdram_ack_s1, sdram_ack_50};
assign sdram_ack = sdram_ack_s2;

always @(posedge fixed_50m_clk) begin
    if (reset) begin
        arb_state <= ARB_IDLE;
        sdram_ack_50 <= 0;
        vid_ack_50 <= 0;
    end else if (ioctl_download) begin
        // Passthrough total para el Loader
        arb_state <= ARB_IDLE;
    end else begin
        case (arb_state)
            ARB_IDLE: begin
                sdram_ack_50 <= 0;
                vid_ack_50 <= 0;
                if (sdram_req_s2) begin
                    arb_state <= ARB_CPU;
                end else if (vid_rd_s2) begin
                    arb_state <= ARB_VIDEO;
                end
            end
            
            ARB_CPU: begin
                if (ddram_dout_ready) begin
                    sdram_buf <= ddram_dout;
                    sdram_ack_50 <= 1;
                    arb_state <= ARB_IDLE;
                end
            end
            
            ARB_VIDEO: begin
                if (ddram_dout_ready) begin
                    // Datos para el motor de video van directos por ddram_dout
                    vid_ack_50 <= 1;
                    arb_state <= ARB_IDLE;
                end
            end
        endcase
    end
end

// Physical SDRAM Mux
assign ddram_addr = ioctl_download ? {5'b0, ioctl_addr[26:3]} :
                    (arb_state == ARB_CPU) ? {5'b0, adr[23:3]} : vid_addr;
                    
assign ddram_we   = ioctl_download && ioctl_wr; 
assign ddram_rd   = ioctl_download ? 1'b0 : 
                    (arb_state == ARB_CPU) ? 1'b1 :
                    (arb_state == ARB_VIDEO) ? 1'b1 : 1'b0;

assign ddram_din  = {4{ioctl_dout}};
assign ddram_be   = ioctl_download ? 
                    ((ioctl_addr[2:1] == 2'd0) ? 8'h03 :
                     (ioctl_addr[2:1] == 2'd1) ? 8'h0C :
                     (ioctl_addr[2:1] == 2'd2) ? 8'h30 : 8'hC0) : 8'hFF;

// El motor de video recibe los datos directamente del bus principal
// Sincronizamos ddram_dout_ready para pgm_video? 
// Por ahora el skeleton asume que el video espera a ddram_busy.

pgm_video video_inst (
    .clk(video_clk),
    .reset(reset),
    
    .vram_addr(vram_addr_vid),
    .vram_dout(vram_dout_vid),
    
    .pal_addr(pal_addr_vid),
    .pal_dout(pal_dout_vid),
    
    .vregs(vregs_packed),
    
    .sprite_addr(spr_addr_vid),
    .sprite_dout(spr_dout_vid),
    
    // SDRAM (Direct connection to physical bus)
    .ddram_rd(vid_rd),
    .ddram_addr(vid_addr),
    .ddram_dout(ddram_dout),
    .ddram_busy(ddram_busy || sdram_req), // Vídeo espera si CPU está usando el bus
    
    .hs(v_hs),
    .vs(v_vs),
    .r(v_r),
    .g(v_g),
    .b(v_b),
    .blank_n(v_blank)
);

// CPU write access to Video RAMs
always @(posedge fixed_20m_clk) begin
    if (!rw_n && !as_n) begin
        if (pal_sel)  pal_ram[adr[11:1]] <= d_out; 
        if (vram_sel) vram[adr[14:1]] <= d_out;
        
        if (vreg_sel) begin
            if (adr[15:12] == 4'h2) zoom_table[adr[4:1]] <= d_out; // B020xx
            else vid_regs[adr[4:1]] <= d_out;
        end
    end
end

endmodule
