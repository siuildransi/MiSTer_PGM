module PGM (
    input         fixed_20m_clk, // 68k Clock
    input         fixed_8m_clk,  // Z80 Clock
    input         reset,

    // MiSTer ioctl interface
    input         ioctl_download,
    input         ioctl_wr,
    input  [26:0] ioctl_addr,
    input  [15:0] ioctl_dout,
    input  [7:0]  ioctl_index,

    // Video Engine interface
    input  [13:1] renderer_vram_addr,
    output [15:0] renderer_vram_dout,
    input  [12:1] renderer_pal_addr,
    output [15:0] renderer_pal_dout,
    output [511:0] vregs_dout,
    input  [10:1] sprite_ram_addr,
    output [15:0] sprite_ram_dout,

    // Audio Outputs
    output [15:0] sample_l,
    output [15:0] sample_r
);

// --- ROM Banking ---
reg [7:0] rom_bank;

// --- 68000 Main CPU (fx68k) ---
wire [23:1] adr;
wire [15:0] d_out;
wire as_n, uds_n, lds_n, rw_n;
reg [15:0] cpu68k_din_reg;
reg cpu68k_dtack_n_reg;

// --- Protection Placeholder ---
wire prot_sel = (adr[23:20] == 4'h1) && !as_n;
reg [15:0] prot_dout;

// Memory Map Decoding
wire bios_sel = (adr[23:17] == 7'b0000000); // 000000-01FFFF
wire ram_sel  = (adr[23:17] == 7'b1000000); // 800000-81FFFF
wire vram_sel = (adr[23:16] == 8'h90) && (adr[15:14] == 2'b00);
wire pal_sel  = (adr[23:13] == 11'b10100000000) && !as_n;
wire vreg_sel = (adr[23:16] == 8'hB0) && !as_n;
wire scroll_sel = (adr[23:12] == 12'h907) && !as_n;

// ==========================================================================
// Block RAMs — Split into separate 8-bit Hi/Lo arrays for M10K inference.
// Quartus Lite cannot infer block RAM from partial byte writes to 16-bit
// arrays. Splitting into 8-bit arrays gives clean full-word writes.
// ==========================================================================

// --- BIOS ROM (16 KB placeholder) ---
(* ramstyle = "no_rw_check" *) reg [7:0] bios_hi [0:8191];
(* ramstyle = "no_rw_check" *) reg [7:0] bios_lo [0:8191];
wire bios_we = ioctl_download && (ioctl_index == 0) && ioctl_wr;

// --- Work RAM (16 KB placeholder) ---
(* ramstyle = "no_rw_check" *) reg [7:0] wram_hi [0:8191];
(* ramstyle = "no_rw_check" *) reg [7:0] wram_lo [0:8191];

// --- Palette RAM (~4.5 KB) ---
(* ramstyle = "no_rw_check" *) reg [7:0] pal_hi [0:2303];
(* ramstyle = "no_rw_check" *) reg [7:0] pal_lo [0:2303];

// --- Video RAM (24 KB) ---
(* ramstyle = "no_rw_check" *) reg [7:0] vram_hi [0:12287];
(* ramstyle = "no_rw_check" *) reg [7:0] vram_lo [0:12287];

// --- Video Registers (tiny, stays as logic) ---
reg [15:0] video_regs [0:31];

// --- Scroll RAM (4 KB) ---
(* ramstyle = "no_rw_check" *) reg [7:0] scroll_hi [0:2047];
(* ramstyle = "no_rw_check" *) reg [7:0] scroll_lo [0:2047];

// ==========================================================================
// Synchronous Write Ports
// ==========================================================================
always @(posedge fixed_20m_clk) begin
    // BIOS ROM load via ioctl
    if (bios_we) begin
        bios_hi[ioctl_addr[13:1]] <= ioctl_dout[15:8];
        bios_lo[ioctl_addr[13:1]] <= ioctl_dout[7:0];
    end

    // Work RAM
    if (ram_sel && !rw_n && !as_n) begin
        if (!uds_n) wram_hi[adr[13:1]] <= d_out[15:8];
        if (!lds_n) wram_lo[adr[13:1]] <= d_out[7:0];
    end

    // Palette RAM
    if (pal_sel && !rw_n) begin
        if (!uds_n) pal_hi[adr[12:1]] <= d_out[15:8];
        if (!lds_n) pal_lo[adr[12:1]] <= d_out[7:0];
    end

    // Video RAM
    if (vram_sel && !rw_n && !as_n) begin
        if (!uds_n) vram_hi[adr[14:1]] <= d_out[15:8];
        if (!lds_n) vram_lo[adr[14:1]] <= d_out[7:0];
    end

    // Video Registers (small, stays as logic)
    if (vreg_sel && !rw_n) begin
        if (!uds_n) video_regs[adr[5:1]][15:8] <= d_out[15:8];
        if (!lds_n) video_regs[adr[5:1]][7:0]  <= d_out[7:0];
    end

    // Scroll RAM
    if (scroll_sel && !rw_n) begin
        if (!uds_n) scroll_hi[adr[11:1]] <= d_out[15:8];
        if (!lds_n) scroll_lo[adr[11:1]] <= d_out[7:0];
    end
end

// ==========================================================================
// Synchronous Read Ports (required for block RAM inference)
// ==========================================================================
reg [7:0] bios_rd_h, bios_rd_l;
reg [7:0] wram_rd_h, wram_rd_l;
reg [7:0] pal_rd_h, pal_rd_l;
reg [7:0] vram_rd_h, vram_rd_l;

always @(posedge fixed_20m_clk) begin
    bios_rd_h <= bios_hi[adr[13:1]];
    bios_rd_l <= bios_lo[adr[13:1]];
    wram_rd_h <= wram_hi[adr[13:1]];
    wram_rd_l <= wram_lo[adr[13:1]];
    pal_rd_h  <= pal_hi[adr[12:1]];
    pal_rd_l  <= pal_lo[adr[12:1]];
    vram_rd_h <= vram_hi[adr[14:1]];
    vram_rd_l <= vram_lo[adr[14:1]];
end

// DTACK and Data Input Multiplexing
always @(*) begin
    cpu68k_dtack_n_reg = 1'b1;
    cpu68k_din_reg = 16'hFFFF;

    if (!as_n) begin
        if (bios_sel) begin
            cpu68k_dtack_n_reg = 1'b0;
            cpu68k_din_reg = {bios_rd_h, bios_rd_l};
        end else if (ram_sel) begin
            cpu68k_dtack_n_reg = 1'b0;
            cpu68k_din_reg = {wram_rd_h, wram_rd_l};
        end else if (pal_sel) begin
            cpu68k_dtack_n_reg = 1'b0;
            cpu68k_din_reg = {pal_rd_h, pal_rd_l};
        end else if (vram_sel) begin
            cpu68k_dtack_n_reg = 1'b0;
            cpu68k_din_reg = {vram_rd_h, vram_rd_l};
        end else if (vreg_sel) begin
            cpu68k_dtack_n_reg = 1'b0;
            cpu68k_din_reg = video_regs[adr[5:1]];
        end else if (prot_sel) begin
            cpu68k_dtack_n_reg = 1'b0;
            cpu68k_din_reg = prot_dout;
        end
    end
end

// ==========================================================================
// 68000 CPU
// ==========================================================================
fx68k main_cpu (
    .clk(fixed_20m_clk),
    .HALTn(1'b1),
    .extReset(reset),
    .pwrUp(reset),
    .enPhi1(1'b1),
    .enPhi2(1'b1),

    .eab(adr),
    .iEdb(cpu68k_din_reg),
    .oEdb(d_out),
    .ASn(as_n),
    .UDSn(uds_n),
    .LDSn(lds_n),
    .eRWn(rw_n),
    .DTACKn(cpu68k_dtack_n_reg),
    .IPL0n(1'b1),
    .IPL1n(1'b1),
    .IPL2n(1'b1),
    .VPAn(1'b1),
    .BRn(1'b1),
    .BGACKn(1'b1),
    .BERRn(1'b1)
);

// ==========================================================================
// Z80 Sound CPU
// ==========================================================================
wire [15:0] z_adr;
wire [7:0]  z_dout;
wire z_mreq_n, z_iorq_n, z_rd_n, z_wr_n;
reg [7:0]   z80_din_reg;

// Z80 Work RAM (4 KB placeholder)
(* ramstyle = "no_rw_check" *) reg [7:0] sound_ram [0:4095];

reg [7:0] latch1, latch2, latch3;

// Synchronous write + read for Z80 sound RAM
reg [7:0] sram_rdata;

always @(posedge fixed_8m_clk) begin
    if (!z_mreq_n && !z_wr_n)
        sound_ram[z_adr[11:0]] <= z_dout;
    sram_rdata <= sound_ram[z_adr[11:0]];
end

// --- ICS2115 Audio Chip ---
wire [15:0] s_l, s_r;
wire ics_we = !z_iorq_n && !z_wr_n && (z_adr[15:8] == 8'h80);
wire ics_re = !z_iorq_n && !z_rd_n && (z_adr[15:8] == 8'h80);
wire [7:0] ics_dout;

ics2115 sound_chip (
    .clk(fixed_8m_clk),
    .reset(reset),
    .addr(z_adr[1:0]),
    .din(z_dout),
    .dout(ics_dout),
    .we(ics_we),
    .re(ics_re),
    .sample_l(s_l),
    .sample_r(s_r)
);

assign sample_l = s_l;
assign sample_r = s_r;

// Z80 Data Mux
always @(*) begin
    z80_din_reg = 8'hFF;
    if (!z_mreq_n) begin
        z80_din_reg = sram_rdata;
    end else if (!z_iorq_n) begin
        case (z_adr[15:8])
            8'h80: z80_din_reg = ics_dout;
            8'h81: z80_din_reg = latch3;
            8'h82: z80_din_reg = latch1;
            8'h84: z80_din_reg = latch2;
            default: z80_din_reg = 8'hFF;
        endcase
    end
end

// 68k Sound Latch Writes
wire latch_sel    = (adr[23:1] == 23'h600001) ||
                    (adr[23:1] == 23'h600002) ||
                    (adr[23:1] == 23'h600006);
wire z80_ctrl_sel = (adr[23:1] == 23'h600005);

always @(posedge fixed_20m_clk) begin
    if (!as_n && !rw_n) begin
        if (latch_sel) begin
            if (adr[23:1] == 23'h600001) latch1 <= d_out[7:0];
            if (adr[23:1] == 23'h600002) latch2 <= d_out[7:0];
            if (adr[23:1] == 23'h600006) latch3 <= d_out[7:0];
        end else if (z80_ctrl_sel) begin
            rom_bank <= d_out[7:0];
        end
    end
end

T80s sound_cpu (
    .RESET_n(~reset),
    .CLK(fixed_8m_clk),
    .WAIT_n(1'b1),
    .INT_n(1'b1),
    .NMI_n(1'b1),
    .BUSRQ_n(1'b1),
    .A(z_adr),
    .DI(z80_din_reg),
    .DO(z_dout),
    .MREQ_n(z_mreq_n),
    .IORQ_n(z_iorq_n),
    .RD_n(z_rd_n),
    .WR_n(z_wr_n)
);

// ==========================================================================
// Video Interface Exports (synchronous reads, second port of dual-port RAM)
// ==========================================================================
reg [7:0] vexp_h, vexp_l, pexp_h, pexp_l, sexp_h, sexp_l;

always @(posedge fixed_20m_clk) begin
    vexp_h <= vram_hi[renderer_vram_addr];
    vexp_l <= vram_lo[renderer_vram_addr];
    pexp_h <= pal_hi[renderer_pal_addr];
    pexp_l <= pal_lo[renderer_pal_addr];
    sexp_h <= wram_hi[sprite_ram_addr];
    sexp_l <= wram_lo[sprite_ram_addr];
end

assign renderer_vram_dout = {vexp_h, vexp_l};
assign renderer_pal_dout  = {pexp_h, pexp_l};
assign sprite_ram_dout    = {sexp_h, sexp_l};

// Video regs flat bus export
genvar i;
generate
    for (i=0; i<32; i=i+1) begin : vregs_export
        assign vregs_dout[16*i +: 16] = video_regs[i];
    end
endgenerate

endmodule
