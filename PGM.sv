module PGM (
    input         fixed_20m_clk,
    input         fixed_8m_clk,
    input         reset,

    // MiSTer ioctl interface
    input         ioctl_download,
    input         ioctl_wr,
    input  [26:0] ioctl_addr,
    input  [15:0] ioctl_dout,
    input  [7:0]  ioctl_index,

    // Audio Outputs
    output [15:0] sample_l,
    output [15:0] sample_r
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

endmodule
