    // Clocks
    input         fixed_20m_clk,
    input         fixed_8m_clk,
    input         video_clk,     // ~25 MHz for Video Timing
    input         reset,

    // MiSTer ioctl interface
    input         ioctl_download,
    input         ioctl_wr,
    input  [26:0] ioctl_addr,
    input  [15:0] ioctl_dout,
    input  [7:0]  ioctl_index,

    // DDRAM Interface (for Sprites)
    output        ddram_rd,
    output [28:0] ddram_addr,
    input  [63:0] ddram_dout,
    input         ddram_busy,

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

// Tiny BIOS placeholder (256 words = 512 bytes)
(* ramstyle = "no_rw_check" *) reg [7:0] bios_hi [0:255];
(* ramstyle = "no_rw_check" *) reg [7:0] bios_lo [0:255];

// Tiny Work RAM (256 words = 512 bytes)
(* ramstyle = "no_rw_check" *) reg [7:0] wram_hi [0:255];
(* ramstyle = "no_rw_check" *) reg [7:0] wram_lo [0:255];

wire bios_sel = (adr[23:17] == 7'b0000000);
wire ram_sel  = (adr[23:17] == 7'b1000000);

// BIOS write from ioctl
always @(posedge fixed_20m_clk) begin
    if (ioctl_download && (ioctl_index == 0) && ioctl_wr) begin
        bios_hi[ioctl_addr[8:1]] <= ioctl_dout[15:8];
        bios_lo[ioctl_addr[8:1]] <= ioctl_dout[7:0];
    end
end

// Work RAM write
always @(posedge fixed_20m_clk) begin
    if (ram_sel && !rw_n && !as_n) begin
        if (!uds_n) wram_hi[adr[8:1]] <= d_out[15:8];
        if (!lds_n) wram_lo[adr[8:1]] <= d_out[7:0];
    end
end

// Synchronous reads
reg [7:0] bios_rd_h, bios_rd_l, wram_rd_h, wram_rd_l;

always @(posedge fixed_20m_clk) begin
    bios_rd_h <= bios_hi[adr[8:1]];
    bios_rd_l <= bios_lo[adr[8:1]];
    wram_rd_h <= wram_hi[adr[8:1]];
    wram_rd_l <= wram_lo[adr[8:1]];
end

// Data mux
always @(*) begin
    cpu68k_dtack_n = 1'b1;
    cpu68k_din = 16'hFFFF;
    if (!as_n) begin
        if (bios_sel) begin
            cpu68k_dtack_n = 1'b0;
            cpu68k_din = {bios_rd_h, bios_rd_l};
        end else if (ram_sel) begin
            cpu68k_dtack_n = 1'b0;
            cpu68k_din = {wram_rd_h, wram_rd_l};
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
wire [13:1] vram_addr_vid;
wire [15:0] vram_dout_vid = vram[vram_addr_vid];

wire [12:1] pal_addr_vid;
wire [15:0] pal_dout_vid = pal_ram[pal_addr_vid];

wire [10:1] spr_addr_vid;
// Sprite data comes from Main Work RAM (High/Low split in PGM.sv)
// We need to fetch 16-bit words from wram_hi/lo using spr_addr_vid
wire [15:0] spr_dout_vid = {wram_hi[spr_addr_vid[8:1]], wram_lo[spr_addr_vid[8:1]]}; 
// Note: spr_addr_vid is 10 bits (word address), wram is 256 words deep in this skeleton? 
// Current skeleton wram is too small (256 bytes). 
// Accessing index [8:1] (8 bits) is OK for 256 size.

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
    
    // SDRAM (Connected to DDRAM in emu.sv)
    .ddram_rd(ddram_rd),
    .ddram_addr(ddram_addr),
    .ddram_dout(ddram_dout),
    .ddram_busy(ddram_busy),
    
    .hs(v_hs),
    .vs(v_vs),
    .r(v_r),
    .g(v_g),
    .b(v_b),
    .blank_n(v_blank)
);

// CPU write access to Video RAMs
wire pal_sel  = (adr[23:17] == 7'b1010000); // A0xxxx
wire vram_sel = (adr[23:17] == 7'b1001000); // 90xxxx
wire vreg_sel = (adr[23:16] == 8'hB0);      // B0xxxx

always @(posedge fixed_20m_clk) begin
    if (!rw_n && !as_n) begin
        if (pal_sel)  pal_ram[adr[12:1]] <= d_out; 
        // Note: pal_ram is 16-bit, CPU writes 16-bit usually.
        // If UDS/LDS split needed, we need to split pal_ram like wram.
        // For skeleton, assuming 16-bit writes for now.
        
        if (vram_sel) vram[adr[15:1]] <= d_out;
        
        if (vreg_sel) begin
            if (adr[15:12] == 4'h2) zoom_table[adr[4:1]] <= d_out; // B020xx
            else vid_regs[adr[4:1]] <= d_out;
        end
    end
end

endmodule
