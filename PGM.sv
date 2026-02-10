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
    output [12:1] renderer_pal_addr,
    input  [15:0] renderer_pal_dout,
    output [511:0] vregs_dout,
    output [10:1] sprite_ram_addr,
    input  [15:0] sprite_ram_dout,

    // Audio Outputs
    output [15:0] sample_l,
    output [15:0] sample_r
);

// --- ROM Banking ---
reg [7:0] rom_bank;
wire [23:1] bank_adr = {rom_bank[4:0], adr[18:1]}; // 512KB banks

// --- Demon Front Protection (ARM7 HLE) ---
// 100000 - 1FFFFF: Protection Area
wire prot_sel = (adr[23:20] == 4'h1) && !as_n;
reg [15:0] prot_dout;

always @(*) begin
    prot_dout = 16'hFFFF;
    if (prot_sel) begin
        // Demon Front protection bypass logic
        // Based on research, we often need to return specific values 
        // to pass the ARM check. Returning 0 is a common first attempt.
        prot_dout = 16'h0000; 
    end
end

// --- 68000 Main CPU (fx68k) ---
wire [23:1] adr;
wire [15:0] d_out;
wire as_n, uds_n, lds_n, rw_n;
reg [15:0] cpu68k_din_reg;
reg cpu68k_dtack_n_reg;

// Memory Map Decoding
// 000000 - 01FFFF: BIOS ROM (ROM 1)
// 800000 - 81FFFF: Main Work RAM
// 900000 - 905FFF: Video RAM (Background/Text)

wire bios_sel = (adr[23:17] == 7'b0000000); // 000000-01FFFF
wire ram_sel  = (adr[23:17] == 7'b1000000); // 800000-81FFFF
wire vram_sel = (adr[23:17] == 7'b1001000) && (adr[16:15] == 2'b00); // 900000-907FFF (approx)

// --- BIOS ROM (128 KB) ---
reg [15:0] bios_rom [0:65535];
wire bios_we = ioctl_download && (ioctl_index == 0) && ioctl_wr;

// --- Work RAM (128 KB) ---
reg [15:0] work_ram [0:65535];
wire ram_we = ram_sel && !rw_n && !as_n;

always @(posedge fixed_20m_clk) begin
    if (bios_we) bios_rom[ioctl_addr[16:1]] <= ioctl_dout;
    if (ram_we) begin
        if (!uds_n) work_ram[adr[16:1]][15:8] <= d_out[15:8];
        if (!lds_n) work_ram[adr[16:1]][7:0]  <= d_out[7:0];
    end
end

// --- Palette RAM (A00000 - A011FF, 4.5 KB) ---
reg [15:0] palette_ram [0:2303];
wire pal_we = (adr[23:13] == 11'b10100000000) && !rw_n && !as_n; // A00000-A01FFF (approx)

// --- Video RAM (Tilemaps, 900000 - 905FFF) ---
// 900000: Background Layer
// 904000: Text Layer
reg [15:0] video_ram [0:12287]; // 24KB total
wire vram_we = vram_sel && !rw_n && !as_n;

always @(posedge fixed_20m_clk) begin
    if (pal_we) begin
        if (!uds_n) palette_ram[adr[12:1]][15:8] <= d_out[15:8];
        if (!lds_n) palette_ram[adr[12:1]][7:0]  <= d_out[7:0];
    end
    if (vram_we) begin
        if (!uds_n) video_ram[adr[14:1]][15:8] <= d_out[15:8];
        if (!lds_n) video_ram[adr[14:1]][7:0]  <= d_out[7:0];
    end
end

// --- Video Registers (B00000 - B0FFFF) ---
reg [15:0] video_regs [0:31]; // 32 registers placeholder
wire vreg_sel = (adr[23:16] == 8'b10110000) && !as_n;

// --- Scroll/Priority RAM (907000 - 9077FF) ---
reg [15:0] scroll_ram [0:1023];
wire scroll_sel = (ram_sel && adr[16:11] == 6'b001110); // Check mapping again

always @(posedge fixed_20m_clk) begin
    if (vreg_sel && !rw_n) begin
        if (!uds_n) video_regs[adr[5:1]][15:8] <= d_out[15:8];
        if (!lds_n) video_regs[adr[5:1]][7:0]  <= d_out[7:0];
    end
    if (scroll_sel && !rw_n && !as_n) begin
        if (!uds_n) scroll_ram[adr[10:1]][15:8] <= d_out[15:8];
        if (!lds_n) scroll_ram[adr[10:1]][7:0]  <= d_out[7:0];
    end
end

// DTACK and Data In Multiplexing (Updated)
always @(*) begin
    cpu68k_dtack_n_reg = 1'b1;
    cpu68k_din_reg = 16'hFFFF;
    
    if (!as_n) begin
        if (bios_sel) begin
            cpu68k_dtack_n_reg = 1'b0;
            cpu68k_din_reg = bios_rom[adr[16:1]];
        end else if (ram_sel) begin
            cpu68k_dtack_n_reg = 1'b0;
            cpu68k_din_reg = work_ram[adr[16:1]];
        end else if (adr[23:13] == 11'b10100000000) begin // Palette
            cpu68k_dtack_n_reg = 1'b0;
            cpu68k_din_reg = palette_ram[adr[12:1]];
        end else if (vram_sel) begin
            cpu68k_dtack_n_reg = 1'b0;
            cpu68k_din_reg = video_ram[adr[14:1]];
        end else if (vreg_sel) begin
            cpu68k_dtack_n_reg = 1'b0;
            cpu68k_din_reg = video_regs[adr[5:1]];
        end else if (prot_sel) begin
            cpu68k_dtack_n_reg = 1'b0;
            cpu68k_din_reg = prot_dout;
        end else begin
            cpu68k_dtack_n_reg = 1'b1; 
        end
    end
end

fx68k main_cpu (
    .clk(fixed_20m_clk),
    .extReset(reset),
    .pwrReset(reset),
    .enPhi1(1'b1),
    .enPhi2(1'b1),

    .addr(adr),
    .din(cpu68k_din_reg),
    .dout(d_out),
    .as_n(as_n),
    .uds_n(uds_n),
    .lds_n(lds_n),
    .rw_n(rw_n),
    .dtack_n(cpu68k_dtack_n_reg),
    .ipl_n(3'b111), // No interrupts for now
    .vpa_n(1'b1),
    .br_n(1'b1),
    .bgack_n(1'b1),
    .berr_n(1'b1)
);

// --- Z80 Sound CPU (T80s) ---
wire [15:0] z_adr;
wire [7:0]  z_dout;
wire z_mreq_n, z_iorq_n, z_rd_n, z_wr_n;
reg [7:0]   z80_din_reg;

// Z80 Work RAM (64 KB)
reg [7:0] sound_ram [0:65535];
wire z_ram_we = !z_mreq_n && !z_wr_n;

// Sound Latches (Communication between 68k and Z80)
// C00002/3: Latch 1
// C00004/5: Latch 2
// C0000C/D: Latch 3
reg [7:0] latch1, latch2, latch3;

always @(posedge fixed_8m_clk) begin
    if (z_ram_we) sound_ram[z_adr] <= z_dout;
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

// Z80 Data In Multiplexing (Updated)
always @(*) begin
    z80_din_reg = 8'hFF;
    if (!z_mreq_n) begin
        z80_din_reg = sound_ram[z_adr];
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

// 68k Access to Sound Latches and Z80 RAM Control
// C00008: Z80 Reset (Write 1 to reset, 0 to run)
// C0000A: Z80 Bank / Control
wire latch_sel = (adr[23:1] == 23'hC00002 >> 1) || 
                 (adr[23:1] == 23'hC00004 >> 1) || 
                 (adr[23:1] == 23'hC0000C >> 1);
wire z80_ctrl_sel = (adr[23:1] == 23'hC0000A >> 1);

always @(posedge fixed_20m_clk) begin
    if (!as_n && !rw_n) begin
        if (latch_sel) begin
            if (adr[23:1] == 23'hC00002 >> 1) latch1 <= d_out[7:0];
            if (adr[23:1] == 23'hC00004 >> 1) latch2 <= d_out[7:0];
            if (adr[23:1] == 23'hC0000C >> 1) latch3 <= d_out[7:0];
        end else if (z80_ctrl_sel) begin
            rom_bank <= d_out[7:0]; // Example: Bank ROM for 68k or Z80
        end
    end
end

T80s sound_cpu (
    .RESET_n(~reset),
    .CLK_n(fixed_8m_clk),
    .WAIT_n(1'b1),
    .INT_n(1'b1),
    .NMI_n(1'b1),
    .BUSRQ_n(1'b1),
    .Addr(z_adr),
    .DI(z80_din_reg),
    .DO(z_dout),
    .MREQ_n(z_mreq_n),
    .IORQ_n(z_iorq_n),
    .RD_n(z_rd_n),
    .WR_n(z_wr_n)
);

// --- Video Interface Exports ---
assign renderer_vram_dout = video_ram[renderer_vram_addr];
assign renderer_pal_dout  = palette_ram[renderer_pal_addr];
assign sprite_ram_dout    = work_ram[sprite_ram_addr];

genvar i;
generate
    for (i=0; i<32; i=i+1) begin : vregs_export
        assign vregs_dout[16*i +: 16] = video_regs[i];
    end
endgenerate

endmodule
