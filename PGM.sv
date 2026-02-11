module PGM (
    // Clocks
    input         fixed_20m_clk,  // Dominio CPU 68k (8.468MHz ~ 20MHz en este core)
    input         fixed_8m_clk,   // Dominio CPU Z80 (8.468MHz)
    input         fixed_50m_clk,  // Dominio Árbitro SDRAM
    input         video_clk,      // Dominio Motor Video (~25.17 MHz)
    input         reset,

    // Interfaz ioctl de MiSTer
    input         ioctl_download,
    input         ioctl_wr,
    input  [26:0] ioctl_addr,
    input  [15:0] ioctl_dout,
    input  [7:0]  ioctl_index,
    output        ioctl_wait,

    // Joysticks and Buttons
    input  [31:0] joystick_0,
    input  [31:0] joystick_1,
    input  [15:0] joy_buttons,

    // DDRAM Interface (Shared by Video and Loader)
    output        ddram_rd,
    output        ddram_we,       // Added
    output [28:0] ddram_addr,
    output [63:0] ddram_din,      // Added
    output [7:0]  ddram_be,       // Added
    input  [63:0] ddram_dout,
    input         ddram_busy,
    input         ddram_dout_ready, // Added

    // Salidas de Audio
    output [15:0] sample_l,
    output [15:0] sample_r,

    // Salidas de Vídeo
    output [7:0]  v_r,
    output [7:0]  v_g,
    output [7:0]  v_b,
    output        v_hs,
    output        v_vs,
    output        v_blank_n,
    output [7:0]  diagnostic_leds
);

// --- 68000 Main CPU (fx68k) ---
wire [23:1] adr;
wire [15:0] d_out;
wire as_n, uds_n, lds_n, rw_n;
reg [15:0] cpu68k_din;
reg cpu68k_dtack_n;

// Decodificación de Memoria (Mapa PGM)
wire bios_sel  = (adr[23:20] == 4'h0);      // 000000 - 0FFFFF (BIOS en SDRAM)
wire prom_sel  = (adr[23:20] >= 4'h1 && adr[23:20] <= 4'h9); // 100000 - 9FFFFF (P-ROM en SDRAM)
wire ram_sel   = (adr[23:17] == 7'b1000000); // 800000 - 81FFFF (Work RAM)
wire vram_sel  = (adr[23:17] == 7'b1001000); // 900000 - 907FFF (VRAM)
wire pal_sel   = (adr[23:17] == 7'b1010000); // A00000 - A011FF (Paleta)
wire vreg_sel  = (adr[23:16] == 8'hB0);      // B00000 - B0FFFF (Registros)
wire io_sel    = (adr[23:16] == 8'hC0);      // C00000 - C0FFFF (I/O, Sound Latch)
wire prot_sel  = (adr[23:16] == 8'h40);      // 400000 - 40FFFF (Protección Tipo 3)

// --- Main Work RAM (128KB = 64K words) via dpram_dc ---
// Puerto A: CPU 68k (20MHz) - lectura/escritura
// Puerto B: Motor de vídeo (video_clk) - solo lectura de sprites
wire wram_we_h = ram_sel && !rw_n && !as_n && !uds_n;
wire wram_we_l = ram_sel && !rw_n && !as_n && !lds_n;
wire [7:0] wram_rd_h, wram_rd_l;
wire [7:0] wram_vid_h, wram_vid_l;

dpram_dc #(16, 8) wram_hi_inst (
    .clk_a(fixed_20m_clk), .we_a(wram_we_h), .addr_a(adr[16:1]),
    .din_a(d_out[15:8]),   .dout_a(wram_rd_h),
    .clk_b(video_clk),    .we_b(1'b0), .addr_b({5'd0, spr_addr_vid[11:1]}), .din_b(8'h00), .dout_b(wram_vid_h)
);

dpram_dc #(16, 8) wram_lo_inst (
    .clk_a(fixed_20m_clk), .we_a(wram_we_l), .addr_a(adr[16:1]),
    .din_a(d_out[7:0]),    .dout_a(wram_rd_l),
    .clk_b(video_clk),    .we_b(1'b0), .addr_b({5'd0, spr_addr_vid[11:1]}), .din_b(8'h00), .dout_b(wram_vid_l)
);

// Input Mapping Logic (Active Low)
// PGM Register C08000: Player 1 (Low Byte), Player 2 (High Byte)
// Bit Order (MAME/PGM): 0:UP, 1:DOWN, 2:LEFT, 3:RIGHT, 4:B1(A), 5:B2(B), 6:B3(C), 7:B4(D)
wire [15:0] pgm_inputs = ~{
    joystick_1[7], joystick_1[6], joystick_1[5], joystick_1[4], 
    joystick_1[3], joystick_1[2], joystick_1[1], joystick_1[0], // P2
    joystick_0[7], joystick_0[6], joystick_0[5], joystick_0[4], 
    joystick_0[3], joystick_0[2], joystick_0[1], joystick_0[0]  // P1
};

// PGM Register C08004: System (Low Byte)
// Bit Order: 0:Coin1, 1:Coin2, 2:Start1, 3:Start2, 4:Test, 5:Service...
// MiSTer joystick_0[8] is usually Start, joystick_0[9] is Select (Coin)
wire [15:0] pgm_system = ~{
    8'h00, // High byte unused/reserved
    4'b0000, 
    joystick_1[8], joystick_0[8], // Start 2, Start 1
    joystick_1[9], joystick_0[9]  // Coin 2, Coin 1
};

// Interfaz SDRAM y Lógica DTACK
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
            // Byte swap for 68k (Big Endian)
            cpu68k_din = {sdram_data[7:0], sdram_data[15:8]};
            if (sdram_ack) cpu68k_dtack_n = 1'b0;
        end else if (vram_sel) begin
            cpu68k_dtack_n = 1'b0;
            cpu68k_din = vram_dout_vid;
        end else if (pal_sel) begin
            cpu68k_dtack_n = 1'b0;
            cpu68k_din = pal_dout_vid;
        end else if (io_sel) begin
            cpu68k_dtack_n = 1'b0;
            cpu68k_din = 16'hFFFF;
            if (adr[15:1] == 15'h0001) cpu68k_din = {8'h00, sound_latch_1}; // C00002 R (MAME)
            if (adr[15:1] == 15'h0002) cpu68k_din = {8'h00, sound_latch_2}; // C00004 R
            if (adr[15:1] == 15'h4000) cpu68k_din = pgm_inputs;            // C08000
            if (adr[15:1] == 15'h4002) cpu68k_din = pgm_system;            // C08004
        end else if (prot_sel) begin
            cpu68k_dtack_n = prot_dtack_n;
            cpu68k_din = prot_dout;
        end
    end
end

// 68k Write to Latches
always @(posedge fixed_20m_clk) begin
    if (reset) begin
        sound_latch_1 <= 0;
        z80_nmi_req <= 0;
    end else if (!as_n && !rw_n && io_sel) begin
        if (adr[15:1] == 15'h0001 && !lds_n) begin
            sound_latch_1 <= d_out[7:0]; // C00002
            z80_nmi_req <= 1; // Trigger NMI
        end
    end else if (z80_nmi_ack_20) begin
        z80_nmi_req <= 0;
    end
end

// Sincronización de Ack NMI de 8MHz a 20MHz
reg z80_nmi_ack_20;
always @(posedge fixed_20m_clk) z80_nmi_ack_20 <= z80_nmi_ack_8m;

// --- IRQ de VBLANK (Nivel 6) ---
reg vblank_irq;
reg vs_s1, vs_s2;
always @(posedge fixed_20m_clk) begin
    vs_s1 <= v_vs;
    vs_s2 <= vs_s1;
    if (vs_s1 && !vs_s2) vblank_irq <= 1; // Start of VS
    else if (!vs_s1 && vs_s2) vblank_irq <= 0; // End of VS
end

wire [2:0] ipl_n = vblank_irq ? 3'b001 : 3'b111; // Level 6 or None

// --- Generación de Reloj para fx68k ---
// El 68000 requiere fases phi1 y phi2 alternas.
// Con el clk de 25MHz, generamos estas fases a 12.5MHz.
reg phi_state;
always @(posedge fixed_20m_clk) begin
    if (reset) phi_state <= 0;
    else phi_state <= ~phi_state;
end
wire cpu_enPhi1 = phi_state;
wire cpu_enPhi2 = ~phi_state;

fx68k main_cpu (
    .clk(fixed_20m_clk),
    .HALTn(1'b1),
    .extReset(reset),
    .pwrUp(reset),
    .enPhi1(cpu_enPhi1),
    .enPhi2(cpu_enPhi2),
    .eab(adr),
    .iEdb(cpu68k_din),
    .oEdb(d_out),
    .ASn(as_n),
    .UDSn(uds_n),
    .LDSn(lds_n),
    .eRWn(rw_n),
    .DTACKn(cpu68k_dtack_n),
    .IPL0n(ipl_n[0]),
    .IPL1n(ipl_n[1]),
    .IPL2n(ipl_n[2]),
    .VPAn(1'b1),
    .BRn(1'b1),
    .BGACKn(1'b1),
    .BERRn(1'b1)
);

// --- Z80 Sound CPU ---
wire [15:0] z_adr;
wire [7:0]  z_dout;
wire z_mreq_n, z_iorq_n, z_rd_n, z_wr_n;
reg  [7:0]  z_din;

reg [7:0] sound_latch_1; // 68k -> Z80
reg [7:0] sound_latch_2; // Z80 -> 68k
reg       z80_nmi_req;
reg       z80_nmi_ack_8m;

// RAM de Sonido (64KB - compartida con el cargador)
wire [7:0] sram_dout_8m;
dpram_dc #(16, 8) sound_ram (
    .clk_a(fixed_50m_clk),
    .we_a(ioctl_download && ioctl_wr && ioctl_index == 1),
    .addr_a(ioctl_addr[15:0]),
    .din_a(ioctl_dout[7:0]),
    
    .clk_b(fixed_8m_clk),
    .we_b(!z_mreq_n && !z_wr_n),
    .addr_b(z_adr),
    .din_b(z_dout),
    .dout_b(sram_dout_8m)
);

// Decodificación de E/S del Z80
wire [7:0] ics2115_dout;
always @(*) begin
    z_din = 8'hFF;
    if (!z_mreq_n && !z_rd_n) begin
        z_din = sram_dout_8m;
    end else if (!z_iorq_n && !z_rd_n) begin
        case (z_adr[7:0])
            8'h00: z_din = sound_latch_1;
            8'h01: z_din = 8'h00; // Estado de IRQ?
            8'h02, 8'h03: z_din = ics2115_dout;
            default: z_din = 8'hFF;
        endcase
    end
end

always @(posedge fixed_8m_clk) begin
    if (reset) begin
        sound_latch_2 <= 0;
        z80_nmi_ack_8m <= 0;
    end else begin
        z80_nmi_ack_8m <= 0;
        if (!z_iorq_n && !z_wr_n) begin
            if (z_adr[7:0] == 8'h00) sound_latch_2 <= z_dout;
        end
        if (!z_iorq_n && !z_rd_n) begin
            if (z_adr[7:0] == 8'h00) z80_nmi_ack_8m <= 1; // Ack NMI al leer
        end
    end
end

T80s sound_cpu (
    .RESET_n(~reset),
    .CLK(fixed_8m_clk),
    .WAIT_n(1'b1),
    .INT_n(1'b1),
    .NMI_n(~z80_nmi_req), // Active Low
    .BUSRQ_n(1'b1),
    .A(z_adr),
    .DI(z_din),
    .DO(z_dout),
    .MREQ_n(z_mreq_n),
    .IORQ_n(z_iorq_n),
    .RD_n(z_rd_n),
    .WR_n(z_wr_n)
);

ics2115 ics2115_inst (
    .clk(fixed_8m_clk), // Ajustar si necesita 33MHz
    .reset(reset),
    .addr({1'b0, z_adr[0]}), // 0x02 -> 0, 0x03 -> 1
    .din(z_dout),
    .dout(ics2115_dout),
    .we(!z_iorq_n && !z_wr_n && (z_adr[7:0] == 8'h02 || z_adr[7:0] == 8'h03)),
    .re(!z_iorq_n && !z_rd_n && (z_adr[7:0] == 8'h02 || z_adr[7:0] == 8'h03)),
    
    // SDRAM (Samples)
    .sdram_rd(sound_rd),
    .sdram_addr(sound_addr),
    .sdram_dout(ddram_dout),
    .sdram_busy(ddram_busy || sdram_req || vid_rd), // Audio tiene prioridad baja
    .sdram_dout_ready(sound_ack),

    .sample_l(ics2115_l),
    .sample_r(ics2115_r)
);

wire [15:0] ics2115_l, ics2115_r;

// --- Diagnostic Audio (Beeps) ---
reg [23:0] beep_cnt;
always @(posedge fixed_50m_clk) beep_cnt <= beep_cnt + 1'd1;

// Unconditional heartbeat: always-on ~380Hz tone (proves audio path works)
wire beep_heartbeat = beep_cnt[16];

wire beep_vblank = beep_cnt[15] & v_vs;      // ~760Hz tone when VSync is high
wire beep_cpu    = beep_cnt[14] & sdram_req; // ~1.5kHz tone during ROM fetch
wire beep_io     = beep_cnt[13] & io_sel;    // ~3kHz tone during I/O access

// Mix diagnostics into final samples
// Mezclar diagnósticos en las muestras finales
// Solo silenciar durante la descarga de la ROM (ioctl_download)
// Mantenemos el pitido durante el reset para confirmar que el audio funciona
wire beep_z80 = beep_cnt[12] & z80_nmi_req & beep_cnt[22]; // ~6kHz tone modulated at ~6Hz (Chirp)

wire [15:0] diag_raw = (beep_heartbeat ? 16'h1000 : 16'h0) +
                       (beep_vblank    ? 16'h0800 : 16'h0) + 
                       (beep_cpu       ? 16'h0800 : 16'h0) + 
                       (beep_io        ? 16'h0800 : 16'h0) +
                       (beep_z80       ? 16'h0800 : 16'h0);

wire [15:0] diag_out = ioctl_download ? 16'h0000 : diag_raw;

assign sample_l = ics2115_l + diag_out;
assign sample_r = ics2115_r + diag_out;

// --- LED Diagnostics ---
// Mapeo optimizado para placas de 3 LEDs (Power, Disk, User)
// Se apagan todos si el sistema está en reset.
assign diagnostic_leds = reset ? 8'h00 : {
    reset,          // Bit 7
    2'b00, 
    io_active_lat,  // Bit 5: CPU I/O activity (LED User)
    beep_cnt[23],   // Bit 4: System Heartbeat (LED Power)
    z80_nmi_req,    // Bit 3
    v_vs,           // Bit 2: Video Activity (LED Disk)
    sd_ack_50_lat,  // Bit 1
    !as_n           // Bit 0
};

reg sd_ack_50_lat;
reg io_active_lat;
always @(posedge fixed_50m_clk) begin
    if (reset) begin
        sd_ack_50_lat <= 0;
        io_active_lat <= 0;
    end else begin
        // Stretch SDRAM Ack
        if (sdram_ack_50) sd_ack_50_lat <= 1;
        else if (beep_cnt[18]) sd_ack_50_lat <= 0;
        
        // Stretch I/O selection (Cpu accesses C0xxxx)
        if (io_sel) io_active_lat <= 1;
        else if (beep_cnt[20]) io_active_lat <= 0;
    end
end

// Señales de sincronización SDRAM de Audio
wire        sound_rd;
wire [28:0] sound_addr;
wire        sound_ack;
wire        sound_ack_20; // Reutilizamos lógica de sincronización

// --- Video System ---

// Video RAMs via dpram_dc (CPU write en 20MHz, Video read en video_clk)
wire [14:1] vram_addr_vid;
wire [15:0] vram_dout_vid;
wire vram_we = vram_sel && !rw_n && !as_n;

dpram_dc #(14, 16) vram_inst (
    .clk_a(fixed_20m_clk), .we_a(vram_we), .addr_a(adr[14:1]),
    .din_a(d_out),         .dout_a(),
    .clk_b(video_clk),    .we_b(1'b0), .addr_b(vram_addr_vid), .din_b(16'h0000), .dout_b(vram_dout_vid)
);

wire [12:1] pal_addr_vid;
wire [15:0] pal_dout_vid;
wire pal_we = pal_sel && !rw_n && !as_n;

dpram_dc #(11, 16) pal_inst (
    .clk_a(fixed_20m_clk), .we_a(pal_we), .addr_a(adr[11:1]),
    .din_a(d_out),         .dout_a(),
    .clk_b(video_clk),    .we_b(1'b0), .addr_b(pal_addr_vid[11:1]), .din_b(16'h0000), .dout_b(pal_dout_vid)
);

// Zoom Table / Video Regs (pequeños, se quedan como registros)
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

// Datos de Sprites: lectura síncrona vía puerto B de wram
wire [11:1] spr_addr_vid;
wire [15:0] spr_dout_vid = {wram_vid_h, wram_vid_l};

// Interconexiones de Vídeo y SDRAM
wire        vid_rd;
wire [28:0] vid_addr;

// --- Árbitro de SDRAM (Dominio 50MHz) ---

// Sync CPU Request to 50MHz
reg  sdram_req_s1, sdram_req_s2;
always @(posedge fixed_50m_clk) {sdram_req_s2, sdram_req_s1} <= {sdram_req_s1, sdram_req};

// Sync Video Request to 50MHz
reg  vid_rd_s1, vid_rd_s2;
always @(posedge fixed_50m_clk) {vid_rd_s2, vid_rd_s1} <= {vid_rd_s1, vid_rd};

// Sync Audio Request to 50MHz
reg  sound_rd_s1, sound_rd_s2;
always @(posedge fixed_50m_clk) {sound_rd_s2, sound_rd_s1} <= {sound_rd_s1, sound_rd};

reg [1:0] arb_state;
localparam ARB_IDLE   = 2'd0;
localparam ARB_CPU    = 2'd1;
localparam ARB_VIDEO  = 2'd2;
localparam ARB_AUDIO  = 2'd3;

reg        sdram_ack_50;
reg        vid_ack_50;
reg        sound_ack_50;
reg [63:0] sdram_buf;
reg        ioctl_wr_pending;
reg        ddram_rd_issued;  // Pulse control: ensure ddram_rd is only 1 cycle

reg sound_rd_last; // Edge detection for audio
always @(posedge fixed_50m_clk) sound_rd_last <= sound_rd_s2;

assign sdram_data = (adr[2:1] == 2'd0) ? sdram_buf[15:0]  :
                    (adr[2:1] == 2'd1) ? sdram_buf[31:16] :
                    (adr[2:1] == 2'd2) ? sdram_buf[47:32] : sdram_buf[63:48];

// Sync Ack back to domains
reg  sdram_ack_s1, sdram_ack_s2;
always @(posedge fixed_20m_clk) {sdram_ack_s2, sdram_ack_s1} <= {sdram_ack_s1, sdram_ack_50};
assign sdram_ack = sdram_ack_s2;

reg  vid_ack_s1, vid_ack_s2;
always @(posedge video_clk) {vid_ack_s2, vid_ack_s1} <= {vid_ack_s1, vid_ack_50};
wire vid_ack = vid_ack_s2;

// Robust Handshake for sound_ack (50MHz -> 8MHz)
reg sound_ack_hold;
always @(posedge fixed_50m_clk) begin
    if (reset) begin
        sound_ack_hold <= 0;
    end else begin
        if (arb_state == ARB_AUDIO && ddram_dout_ready) begin
            sound_ack_hold <= 1; // Set when data available
        end else if (!sound_rd_s2) begin
            sound_ack_hold <= 0; // Clear ONLY when request is dropped by source
        end
    end
end

reg  sound_ack_s1, sound_ack_s2;
always @(posedge fixed_8m_clk) {sound_ack_s2, sound_ack_s1} <= {sound_ack_s1, sound_ack_hold};
assign sound_ack = sound_ack_s2;

always @(posedge fixed_50m_clk) begin
    if (reset) begin
        arb_state <= ARB_IDLE;
        sdram_ack_50 <= 0;
        vid_ack_50 <= 0;
        ddram_rd_issued <= 0;
    end else if (ioctl_download) begin
        // Passthrough total para el Loader (latch de escritura está en bloque aparte)
        arb_state <= ARB_IDLE;
        ddram_rd_issued <= 0;
    end else begin
        case (arb_state)
            ARB_IDLE: begin
                ddram_rd_issued <= 0;
                // Level-based handshake: only clear ack when request is gone
                if (!sdram_req_s2) sdram_ack_50 <= 0;
                if (!vid_rd_s2)    vid_ack_50   <= 0;
                // Don't start a new transaction while ack is still held
                if (sdram_req_s2 && !sdram_ack_50) begin
                    arb_state <= ARB_CPU;
                end else if (vid_rd_s2 && !vid_ack_50) begin
                    arb_state <= ARB_VIDEO;
                end else if (sound_rd_s2 && !sound_rd_last) begin // Edge detection
                    arb_state <= ARB_AUDIO;
                end
            end
            
            ARB_CPU: begin
                if (!ddram_rd_issued && !ddram_busy) ddram_rd_issued <= 1;
                if (ddram_dout_ready) begin
                    sdram_buf <= ddram_dout;
                    sdram_ack_50 <= 1;
                    arb_state <= ARB_IDLE;
                end
            end
            
            ARB_VIDEO: begin
                if (!ddram_rd_issued && !ddram_busy) ddram_rd_issued <= 1;
                if (ddram_dout_ready) begin
                    vid_ack_50 <= 1;
                    arb_state <= ARB_IDLE;
                end
            end

            ARB_AUDIO: begin
                if (!ddram_rd_issued && !ddram_busy) ddram_rd_issued <= 1;
                if (ddram_dout_ready) begin
                    // sound_ack_50 <= 1; // Removed, using sound_ack_hold logic
                    arb_state <= ARB_IDLE;
                end
            end
        endcase
    end
end

// Physical SDRAM Mux — Loader Write Latch (Avalon-MM compliant)
// Latcheamos addr/data/be cuando llega ioctl_wr para que no cambien
// mientras esperamos a que ddram_busy baje.
reg [28:0] wr_addr_lat;
reg [63:0] wr_data_lat;
reg [7:0]  wr_be_lat;

always @(posedge fixed_50m_clk) begin
    if (reset || !ioctl_download) begin
        ioctl_wr_pending <= 0;
    end else if (ioctl_wr && (ioctl_index == 8'h00) && !ioctl_wr_pending) begin
        ioctl_wr_pending <= 1;
        wr_addr_lat <= {5'b0, ioctl_addr[26:3]};
        wr_data_lat <= {4{ioctl_dout}};
        wr_be_lat   <= (ioctl_addr[2:1] == 2'd0) ? 8'h03 :
                       (ioctl_addr[2:1] == 2'd1) ? 8'h0C :
                       (ioctl_addr[2:1] == 2'd2) ? 8'h30 : 8'hC0;
    end else if (ioctl_wr_pending && !ddram_busy) begin
        ioctl_wr_pending <= 0;
    end
end

// Address Mux
assign ddram_addr = ioctl_download ? wr_addr_lat :
                    (arb_state == ARB_CPU)   ? {5'b0, adr[23:3]} : 
                    (arb_state == ARB_AUDIO) ? sound_addr : vid_addr;

// Write Enable — SOLO durante download con latch activo
assign ddram_we   = ioctl_wr_pending;

// Read Enable — Single pulse: only assert when arbiter has a slot and read not yet issued
assign ddram_rd   = !ioctl_download && (arb_state != ARB_IDLE) && !ddram_rd_issued && !ddram_busy;

// Data/BE — valores latcheados durante download, defaults para lectura
assign ddram_din  = wr_data_lat;
assign ddram_be   = ioctl_wr_pending ? wr_be_lat : 8'hFF;

// Señal de espera: pausa al HPS mientras haya una escritura pendiente
assign ioctl_wait = ioctl_wr_pending;

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
    .ddram_dout_ready(vid_ack),
    
    .hs(v_hs),
    .vs(v_vs),
    .r(v_r),
    .g(v_g),
    .b(v_b),
    .blank_n(v_blank_n)
);

// --- Type 3 Protection (IGS027A HLE) ---
wire [15:0] prot_dout;
wire prot_dtack_n;

igs027a_hle protection_inst (
    .clk(fixed_20m_clk),
    .reset(reset),
    .addr(adr[4:1]),
    .din(d_out),
    .dout(prot_dout),
    .we(prot_sel && !rw_n && !as_n),
    .re(prot_sel && rw_n && !as_n),
    .dtack_n(prot_dtack_n)
);

// CPU write access to Video Regs (VRAM y PAL ya gestionados por dpram_dc)
always @(posedge fixed_20m_clk) begin
    if (!rw_n && !as_n) begin
        if (vreg_sel) begin
            if (adr[15:12] == 4'h2) zoom_table[adr[4:1]] <= d_out; // B020xx
            else vid_regs[adr[4:1]] <= d_out;
        end
    end
end

endmodule
