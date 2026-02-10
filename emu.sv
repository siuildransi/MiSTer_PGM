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

    input         CLK_VIDEO,
    input         CE_PIXEL,
    input  [1:0]  VGA_SL,
    input  [8:0]  VIDEO_ARX,
    input  [8:0]  VIDEO_ARY,

    output [15:0] AUDIO_L,
    output [15:0] AUDIO_R,
    output        AUDIO_S,
    output [1:0]  AUDIO_MIX,

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
    output        SDRAM_CKE
);

// --- HPS IO ---
wire ioctl_download, ioctl_wr;
wire [26:0] ioctl_addr;
wire [15:0] ioctl_dout;
wire [7:0]  ioctl_index;
wire [31:0] status;

hps_io #(.CONF_STR("P,PGM.rbf;O12,Scandoubler,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;")) hps_io (
    .clk_sys(CLK_50M),
    .HPS_BUS(HPS_BUS),
    .ioctl_download(ioctl_download),
    .ioctl_wr(ioctl_wr),
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .ioctl_index(ioctl_index),
    .status(status)
);

// --- PGM Core Logic ---
wire [15:0] sample_l, sample_r;
wire hs, vs, blank_n;
wire [7:0] r, g, b;

PGM pgm_core (
    .fixed_20m_clk(clk_20m),
    .fixed_8m_clk(clk_8m),
    .reset(RESET || ioctl_download),

    // ioctl
    .ioctl_download(ioctl_download),
    .ioctl_wr(ioctl_wr),
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .ioctl_index(ioctl_index),

    // Audio
    .sample_l(sample_l),
    .sample_r(sample_r)
);

assign AUDIO_L = sample_l;
assign AUDIO_R = sample_r;
assign AUDIO_S = 1'b0;
assign AUDIO_MIX = 2'b00;

// --- Video ---
pgm_video video_gen (
    .clk(CLK_50M),
    .reset(RESET),
    .hs(hs),
    .vs(vs),
    .r(r),
    .g(g),
    .b(b),
    .blank_n(blank_n)
);

assign VGA_R = r;
assign VGA_G = g;
assign VGA_B = b;
assign VGA_HS = hs;
assign VGA_VS = vs;
assign VGA_DE = blank_n;

// --- Clocks ---
wire clk_20m, clk_8m;
// Simple dividers for now
reg [1:0] div20;
always @(posedge CLK_50M) div20 <= div20 + 2'd1;
assign clk_20m = div20[1];

reg [2:0] div8;
always @(posedge CLK_50M) div8 <= div8 + 3'd1;
assign clk_8m = div8[2];

endmodule
