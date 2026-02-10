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
reg [15:0] cpu68k_din_reg;
reg cpu68k_dtack_n_reg;

// Memory Map Decoding
// 000000 - 01FFFF: BIOS ROM (ROM 1)
// 800000 - 81FFFF: Main Work RAM
// 900000 - 905FFF: Video RAM (Background/Text)

wire bios_sel = (adr[23:17] == 7'b0000000); // 000000-01FFFF
wire ram_sel  = (adr[23:17] == 7'b1000000); // 800000-81FFFF
wire vram_sel = (adr[23:17] == 7'b1001000) && (adr[16:15] == 2'b00); // 900000-907FFF (approx)

// --- Work RAM (128 KB) ---
reg [15:0] work_ram [0:65535];
wire ram_we = ram_sel && !rw_n && !as_n;

always @(posedge fixed_20m_clk) begin
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

// DTACK and Data In Multiplexing (Updated)
always @(*) begin
    cpu68k_dtack_n_reg = 1'b1;
    cpu68k_din_reg = 16'hFFFF;
    
    if (!as_n) begin
        if (bios_sel) begin
            cpu68k_dtack_n_reg = 1'b0;
            cpu68k_din_reg = 16'h0000;
        end else if (ram_sel) begin
            cpu68k_dtack_n_reg = 1'b0;
            cpu68k_din_reg = work_ram[adr[16:1]];
        end else if (pal_we || (adr[23:13] == 11'b10100000000)) begin
            cpu68k_dtack_n_reg = 1'b0;
            cpu68k_din_reg = palette_ram[adr[12:1]];
        end else if (vram_sel) begin
            cpu68k_dtack_n_reg = 1'b0;
            cpu68k_din_reg = video_ram[adr[14:1]];
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

// Z80 Data In Multiplexing
always @(*) begin
    z80_din_reg = 8'hFF;
    if (!z_mreq_n) begin
        z80_din_reg = sound_ram[z_adr];
    end else if (!z_iorq_n) begin
        case (z_adr[15:8])
            8'h81: z80_din_reg = latch3;
            8'h82: z80_din_reg = latch1;
            8'h84: z80_din_reg = latch2;
            default: z80_din_reg = 8'hFF;
        endcase
    end
end

// 68k Access to Sound Latches and Z80 RAM Control
// (Simplified: in a real PGM, 68k can write to sound RAM)
wire latch_sel = (adr[23:1] == 23'hC00002 >> 1) || 
                 (adr[23:1] == 23'hC00004 >> 1) || 
                 (adr[23:1] == 23'hC0000C >> 1);

always @(posedge fixed_20m_clk) begin
    if (!as_n && !rw_n && latch_sel) begin
        if (adr[23:1] == 23'hC00002 >> 1) latch1 <= d_out[7:0];
        if (adr[23:1] == 23'hC00004 >> 1) latch2 <= d_out[7:0];
        if (adr[23:1] == 23'hC0000C >> 1) latch3 <= d_out[7:0];
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

assign cpuz80_addr   = z_adr;
assign cpuz80_dout   = z_dout;
assign cpuz80_mreq_n = z_mreq_n;
assign cpuz80_iorq_n = z_iorq_n;
assign cpuz80_rd_n   = z_rd_n;
assign cpuz80_wr_n   = z_wr_n;

endmodule
