module PGM (
    input         fixed_20m_clk, // 68k Clock
    input         fixed_8m_clk,  // Z80 Clock
    input         reset,

    // Main 68k Bus
    output [23:1] cpu68k_addr,
    input  [15:0] cpu68k_din,
    output [15:0] cpu68k_dout,
    output        cpu68k_as_n,
    output        cpu68k_uds_n,
    output        cpu68k_lds_n,
    output        cpu68k_rw_n,
    input         cpu68k_dtack_n,

    // Sound Z80 Bus
    output [15:0] cpuz80_addr,
    input  [7:0]  cpuz80_din,
    output [7:0]  cpuz80_dout,
    output        cpuz80_mreq_n,
    output        cpuz80_iorq_n,
    output        cpuz80_rd_n,
    output        cpuz80_wr_n
);

// --- 68000 Main CPU (fx68k) ---
wire [23:1] adr;
wire [15:0] d_out;
wire as_n, uds_n, lds_n, rw_n;

fx68k main_cpu (
    .clk(fixed_20m_clk),
    .extReset(reset),
    .pwrReset(reset),
    .enPhi1(1'b1),
    .enPhi2(1'b1),

    .addr(adr),
    .din(cpu68k_din),
    .dout(d_out),
    .as_n(as_n),
    .uds_n(uds_n),
    .lds_n(lds_n),
    .rw_n(rw_n),
    .dtack_n(cpu68k_dtack_n),
    .ipl_n(3'b111), // No interrupts for now
    .vpa_n(1'b1),
    .br_n(1'b1),
    .bgack_n(1'b1),
    .berr_n(1'b1)
);

assign cpu68k_addr  = adr;
assign cpu68k_dout  = d_out;
assign cpu68k_as_n  = as_n;
assign cpu68k_uds_n = uds_n;
assign cpu68k_lds_n = lds_n;
assign cpu68k_rw_n  = rw_n;

// --- Z80 Sound CPU (T80s) ---
wire [15:0] z_adr;
wire [7:0]  z_dout;
wire z_mreq_n, z_iorq_n, z_rd_n, z_wr_n;

T80s sound_cpu (
    .RESET_n(~reset),
    .CLK_n(fixed_8m_clk),
    .WAIT_n(1'b1),
    .INT_n(1'b1),
    .NMI_n(1'b1),
    .BUSRQ_n(1'b1),
    .Addr(z_adr),
    .DI(cpuz80_din),
    .DO(z_dout),
    .MREQ_n(z_mreq_n),
    .IORQ_n(z_iorq_n),
    .RD_n(z_rd_n),
    .WR_n(z_wr_n)
);

assign cpuz80_addr   = z_adr;
assign cpuz80_dout   = z_dout;
assign cpuz80_mreq_n = z_mreq_n;
assign cpuz80_iorq_n = z_iorq_n;
assign cpuz80_rd_n   = z_rd_n;
assign cpuz80_wr_n   = z_wr_n;

endmodule
