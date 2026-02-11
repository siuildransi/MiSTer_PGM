module emu (
    input         CLK_50M,
    input         RESET,
    inout  [48:0] HPS_BUS,

    output [7:0]  VGA_R,
    output [7:0]  VGA_G,
    output [7:0]  VGA_B,
    output        VGA_HS,
    output        VGA_VS,
    output        VGA_DE,
    output        VGA_F1,
    output [1:0]  VGA_SCALER,
    output        VGA_DISABLE,

    input  [11:0] HDMI_WIDTH,
    input  [11:0] HDMI_HEIGHT,
    input         HDMI_FREEZE,
    input         HDMI_BLACKOUT,
    input         HDMI_BOB_DEINT,

    // CLK_VIDEO/CE_PIXEL/VGA_SL/VIDEO_ARX/ARY are OUTPUTS from core to framework
    output        CLK_VIDEO,
    output        CE_PIXEL,
    output [1:0]  VGA_SL,
    output [12:0] VIDEO_ARX,
    output [12:0] VIDEO_ARY,

    input         CLK_AUDIO,
    output [15:0] AUDIO_L,
    output [15:0] AUDIO_R,
    output        AUDIO_S,
    output [1:0]  AUDIO_MIX,

    input  [31:0] ADC_BUS,

    output [7:0]  LED_USER,
    output [7:0]  LED_POWER,
    output [7:0]  LED_DISK,

    input  [1:0]  BUTTONS,
    input         OSD_STATUS,

    // SDRAM
    inout  [15:0] SDRAM_DQ,
    output [12:0] SDRAM_A,
    output        SDRAM_DQML,
    output        SDRAM_DQMH,
    output [1:0]  SDRAM_BA,
    output        SDRAM_nCS,
    output        SDRAM_nWE,
    output        SDRAM_nRAS,
    output        SDRAM_nCAS,
    output        SDRAM_CLK,
    output        SDRAM_CKE,

    // DDRAM
    output        DDRAM_CLK,
    output [28:0] DDRAM_ADDR,
    output [3:0]  DDRAM_BURSTCNT,
    input         DDRAM_BUSY,
    input  [63:0] DDRAM_DOUT,
    input         DDRAM_DOUT_READY,
    output        DDRAM_RD,
    output [63:0] DDRAM_DIN,
    output [7:0]  DDRAM_BE,
    output        DDRAM_WE,

    // SD Card
    output        SD_SCK,
    output        SD_MOSI,
    input         SD_MISO,
    output        SD_CS,
    input         SD_CD,

    // UART
    input         UART_CTS,
    output        UART_RTS,
    input         UART_RXD,
    output        UART_TXD,
    output        UART_DTR,
    input         UART_DSR,

    // USER I/O
    output [6:1]  USER_OUT,
    input  [6:1]  USER_IN
);

// --- HPS IO ---
wire ioctl_download, ioctl_wr;
wire [26:0] ioctl_addr;
wire [15:0] ioctl_dout;
wire [7:0]  ioctl_index;
wire [31:0] status;

// --- PGM Core (minimal — CPUs only) ---
wire [15:0] sample_l, sample_r;
wire [31:0] joy0, joy1;

hps_io #(.CONF_STR("P,PGM.rbf;O12,Scandoubler,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;")) hps_io (
    .clk_sys(CLK_50M),
    .HPS_BUS(HPS_BUS),
    .joystick_0(joy0),
    .joystick_1(joy1),
    .ioctl_download(ioctl_download),
    .ioctl_wr(ioctl_wr),
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .ioctl_index(ioctl_index),
    .status(status)
);

PGM pgm_core (
    .fixed_20m_clk(clk_20m),
    .fixed_8m_clk(clk_8m),
    .fixed_50m_clk(CLK_50M),
    .video_clk(clk_vid),
    .reset(RESET || ioctl_download || status[0]),
    .ioctl_download(ioctl_download),
    .ioctl_wr(ioctl_wr),
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .ioctl_index(ioctl_index),
    
    // Joystick/Buttons
    .joystick_0(joy0),
    .joystick_1(joy1),
    .joy_buttons(status[15:0]),
    
    // DDRAM Interface
    .ddram_rd(DDRAM_RD),
    .ddram_we(DDRAM_WE),
    .ddram_addr(DDRAM_ADDR),
    .ddram_din(DDRAM_DIN),
    .ddram_be(DDRAM_BE),
    .ddram_dout(DDRAM_DOUT),
    .ddram_busy(DDRAM_BUSY),
    .ddram_dout_ready(DDRAM_DOUT_READY),
    
    // Audio
    .sample_l(sample_l),
    .sample_r(sample_r),
    
    // Video
    .v_r(core_r),
    .v_g(core_g),
    .v_b(core_b),
    .v_hs(core_hs),
    .v_vs(core_vs),
    .v_blank(core_blank)
);

assign AUDIO_L = sample_l;
assign AUDIO_R = sample_r;
assign AUDIO_S = 1'b0;
assign AUDIO_MIX = 2'b00;

// --- Video Routing ---
wire [7:0] core_r, core_g, core_b;
wire core_hs, core_vs, core_blank;

assign VGA_R  = core_blank ? core_r : 8'h00;
assign VGA_G  = core_blank ? core_g : 8'h00;
assign VGA_B  = core_blank ? core_b : 8'h00;
assign VGA_HS = core_hs;
assign VGA_VS = core_vs;
assign VGA_DE = core_blank;

// Placeholder for logic removed
wire unused_signals = &{1'b0};
// VGA_DE driven by core_blank above
assign VGA_F1 = 1'b0;
assign VGA_SCALER = 2'b00;
assign VGA_DISABLE = 1'b0;

// --- Defaults ---
assign LED_USER  = 8'h00;
assign LED_POWER = 8'h01;
assign LED_DISK  = 8'h00;

assign SDRAM_A    = 13'h0;
assign SDRAM_BA   = 2'b00;
assign SDRAM_DQML = 1'b1;
assign SDRAM_DQMH = 1'b1;
assign SDRAM_nCS  = 1'b1;
assign SDRAM_nWE  = 1'b1;
assign SDRAM_nRAS = 1'b1;
assign SDRAM_nCAS = 1'b1;
assign SDRAM_CLK  = 1'b0;
assign SDRAM_CKE  = 1'b0;

assign DDRAM_CLK      = 1'b0;
// DDRAM_ADDR driven by PGM
assign DDRAM_BURSTCNT = 4'h0;
// DDRAM_RD driven by PGM
// DDRAM_DIN driven by PGM
// DDRAM_BE driven by PGM
// DDRAM_WE driven by PGM

assign SD_SCK  = 1'b0;
assign SD_MOSI = 1'b0;
assign SD_CS   = 1'b1;

assign UART_RTS = 1'b0;
assign UART_TXD = 1'b1;
assign UART_DTR = 1'b1;

assign USER_OUT = 6'b000000;

endmodule
