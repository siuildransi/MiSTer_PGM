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
wire [23:1] bank_adr = {rom_bank[4:0], adr[18:1]}; // 512KB banks

// --- 68000 Main CPU (fx68k) ---
wire [23:1] adr;
wire [15:0] d_out;
wire as_n, uds_n, lds_n, rw_n;
reg [15:0] cpu68k_din_reg;
reg cpu68k_dtack_n_reg;

// --- Demon Front Protection (ARM7 HLE) ---
wire prot_sel = (adr[23:20] == 4'h1) && !as_n;
reg [15:0] prot_dout;

// Memory Map Decoding
// 000000 - 01FFFF: BIOS ROM (128KB, reduced to 16KB placeholder)
// 800000 - 81FFFF: Main Work RAM (128KB, reduced to 16KB placeholder)
// 900000 - 905FFF: Video RAM (24KB)

wire bios_sel = (adr[23:17] == 7'b0000000); // 000000-01FFFF
wire ram_sel  = (adr[23:17] == 7'b1000000); // 800000-81FFFF
wire vram_sel = (adr[23:16] == 8'h90) && (adr[15:14] == 2'b00); // 900000-903FFF + 904000-905FFF

// ==========================================================================
// Block RAM memories with M10K inference
// All reads MUST be synchronous (registered) for M10K block RAM inference.
// Sizes reduced until SDRAM controller is implemented.
// ==========================================================================

// --- BIOS ROM (16 KB placeholder — real core uses SDRAM) ---
(* ramstyle = "M10K" *) reg [15:0] bios_rom [0:8191]; // 8K x 16 = 16KB
wire bios_we = ioctl_download && (ioctl_index == 0) && ioctl_wr;

// --- Work RAM (16 KB placeholder — real core uses SDRAM) ---
(* ramstyle = "M10K" *) reg [15:0] work_ram [0:8191]; // 8K x 16 = 16KB
wire ram_we = ram_sel && !rw_n && !as_n;

// --- Palette RAM (A00000 - A011FF, ~4.5 KB) ---
(* ramstyle = "M10K" *) reg [15:0] palette_ram [0:2303]; // 2304 x 16

wire pal_sel = (adr[23:13] == 11'b10100000000) && !as_n;
wire pal_we  = pal_sel && !rw_n;

// --- Video RAM (Tilemaps, 24KB) ---
(* ramstyle = "M10K" *) reg [15:0] video_ram [0:12287]; // 12K x 16 = 24KB
wire vram_we = vram_sel && !rw_n && !as_n;

// --- Video Registers (B00000 - B0FFFF, 32 x 16 = 64 bytes, stays as regs) ---
reg [15:0] video_regs [0:31];
wire vreg_sel = (adr[23:16] == 8'hB0) && !as_n;

// --- Scroll/Priority RAM (907000 - 907FFF) ---
(* ramstyle = "M10K" *) reg [15:0] scroll_ram [0:2047]; // 2K x 16 = 4KB
wire scroll_sel = (adr[23:12] == 12'h907) && !as_n;

// ==========================================================================
// Synchronous Write Ports (68k domain)
// ==========================================================================
always @(posedge fixed_20m_clk) begin
    if (bios_we)
        bios_rom[ioctl_addr[13:1]] <= ioctl_dout;

    if (ram_we) begin
        if (!uds_n) work_ram[adr[13:1]][15:8] <= d_out[15:8];
        if (!lds_n) work_ram[adr[13:1]][7:0]  <= d_out[7:0];
    end

    if (pal_we) begin
        if (!uds_n) palette_ram[adr[12:1]][15:8] <= d_out[15:8];
        if (!lds_n) palette_ram[adr[12:1]][7:0]  <= d_out[7:0];
    end

    if (vram_we) begin
        if (!uds_n) video_ram[adr[14:1]][15:8] <= d_out[15:8];
        if (!lds_n) video_ram[adr[14:1]][7:0]  <= d_out[7:0];
    end

    if (vreg_sel && !rw_n) begin
        if (!uds_n) video_regs[adr[5:1]][15:8] <= d_out[15:8];
        if (!lds_n) video_regs[adr[5:1]][7:0]  <= d_out[7:0];
    end

    if (scroll_sel && !rw_n) begin
        if (!uds_n) scroll_ram[adr[11:1]][15:8] <= d_out[15:8];
        if (!lds_n) scroll_ram[adr[11:1]][7:0]  <= d_out[7:0];
    end
end

// ==========================================================================
// Synchronous Read Ports (68k domain) — Required for M10K inference
// Data is registered: available 1 clock after address presented.
// ==========================================================================
reg [15:0] bios_rdata, ram_rdata, pal_rdata, vram_rdata;

always @(posedge fixed_20m_clk) begin
    bios_rdata <= bios_rom[adr[13:1]];
    ram_rdata  <= work_ram[adr[13:1]];
    pal_rdata  <= palette_ram[adr[12:1]];
    vram_rdata <= video_ram[adr[14:1]];
end

// DTACK and Data In Multiplexing
// Uses registered (synchronous) read data from block RAMs.
// Video regs are small enough to stay combinational.
always @(*) begin
    cpu68k_dtack_n_reg = 1'b1;
    cpu68k_din_reg = 16'hFFFF;

    if (!as_n) begin
        if (bios_sel) begin
            cpu68k_dtack_n_reg = 1'b0;
            cpu68k_din_reg = bios_rdata;
        end else if (ram_sel) begin
            cpu68k_dtack_n_reg = 1'b0;
            cpu68k_din_reg = ram_rdata;
        end else if (pal_sel) begin
            cpu68k_dtack_n_reg = 1'b0;
            cpu68k_din_reg = pal_rdata;
        end else if (vram_sel) begin
            cpu68k_dtack_n_reg = 1'b0;
            cpu68k_din_reg = vram_rdata;
        end else if (vreg_sel) begin
            cpu68k_dtack_n_reg = 1'b0;
            cpu68k_din_reg = video_regs[adr[5:1]]; // Small, stays combinational
        end else if (prot_sel) begin
            cpu68k_dtack_n_reg = 1'b0;
            cpu68k_din_reg = prot_dout;
        end
    end
end

// ==========================================================================
// 68000 CPU Instantiation
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

// Z80 Work RAM (4 KB placeholder — real PGM has 64KB)
(* ramstyle = "M10K" *) reg [7:0] sound_ram [0:4095]; // 4K x 8 = 4KB
wire z_ram_we = !z_mreq_n && !z_wr_n;

// Sound Latches (Communication between 68k and Z80)
reg [7:0] latch1, latch2, latch3;

// Synchronous write + read for Z80 sound RAM
reg [7:0] sram_rdata;

always @(posedge fixed_8m_clk) begin
    if (z_ram_we) sound_ram[z_adr[11:0]] <= z_dout;
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

// Z80 Data In Multiplexing (uses synchronous read from sound_ram)
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

// 68k Access to Sound Latches
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
// Video Interface Exports (synchronous reads for M10K)
// ==========================================================================
reg [15:0] vram_export_rd, pal_export_rd, sprite_export_rd;

always @(posedge fixed_20m_clk) begin
    vram_export_rd   <= video_ram[renderer_vram_addr];
    pal_export_rd    <= palette_ram[renderer_pal_addr];
    sprite_export_rd <= work_ram[sprite_ram_addr];
end

assign renderer_vram_dout = vram_export_rd;
assign renderer_pal_dout  = pal_export_rd;
assign sprite_ram_dout    = sprite_export_rd;

// Video regs exported as flat bus (small enough to stay as regs)
genvar i;
generate
    for (i=0; i<32; i=i+1) begin : vregs_export
        assign vregs_dout[16*i +: 16] = video_regs[i];
    end
endgenerate

endmodule
