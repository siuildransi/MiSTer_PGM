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

// --- Clocks ---
// PLL generates 25.175MHz video clock from 50MHz input.
// CLK_VIDEO must be a PLL output (Quartus requirement for clock switches).
wire clk_vid;
wire pll_locked;

pll vid_pll (
    .refclk(CLK_50M),
    .rst(1'b0),
    .outclk_0(clk_vid),
    .locked(pll_locked)
);

assign CLK_VIDEO = clk_vid;
assign CE_PIXEL  = 1'b1;      // Every PLL clock cycle is a pixel
assign VGA_SL    = 2'b00;     // No scanlines
assign VIDEO_ARX = 13'd4;     // 4:3 aspect ratio
assign VIDEO_ARY = 13'd3;

// --- CPU Clocks ---
// 68k: ~20 MHz (50/2 = 25, close enough for skeleton)
wire clk_20m;
reg [1:0] div20;
always @(posedge CLK_50M) div20 <= div20 + 2'd1;
assign clk_20m = div20[1];

// Z80: ~8 MHz (50/6 ≈ 8.3 MHz)
wire clk_8m;
reg [2:0] div8;
always @(posedge CLK_50M) div8 <= div8 + 3'd1;
assign clk_8m = div8[2];

// --- PGM Core (minimal — CPUs only) ---
wire [15:0] sample_l, sample_r;

PGM pgm_core (
    .fixed_20m_clk(clk_20m),
    .fixed_8m_clk(clk_8m),
    .reset(RESET || ioctl_download),
    .ioctl_download(ioctl_download),
    .ioctl_wr(ioctl_wr),
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .ioctl_index(ioctl_index),
    .sample_l(sample_l),
    .sample_r(sample_r)
);

assign AUDIO_L = sample_l;
assign AUDIO_R = sample_r;
assign AUDIO_S = 1'b0;
assign AUDIO_MIX = 2'b00;

// --- Minimal Video (blank dark screen with sync) ---
reg [9:0] h_cnt;
reg [9:0] v_cnt;

always @(posedge clk_vid) begin
    if (RESET) begin
        h_cnt <= 0;
        v_cnt <= 0;
    end else begin
        if (h_cnt == 799) begin
            h_cnt <= 0;
            if (v_cnt == 524) v_cnt <= 0;
            else v_cnt <= v_cnt + 1'd1;
        end else h_cnt <= h_cnt + 1'd1;
    end
end

wire active = (h_cnt < 640 && v_cnt < 480);

assign VGA_R  = active ? 8'h10 : 8'h00;
assign VGA_G  = active ? 8'h10 : 8'h00;
assign VGA_B  = active ? 8'h30 : 8'h00;
assign VGA_HS = ~(h_cnt >= 656 && h_cnt < 752);
assign VGA_VS = ~(v_cnt >= 490 && v_cnt < 492);
assign VGA_DE = active;
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
assign DDRAM_ADDR     = 29'h0;
assign DDRAM_BURSTCNT = 4'h0;
assign DDRAM_RD       = 1'b0;
assign DDRAM_DIN      = 64'h0;
assign DDRAM_BE       = 8'h0;
assign DDRAM_WE       = 1'b0;

assign SD_SCK  = 1'b0;
assign SD_MOSI = 1'b0;
assign SD_CS   = 1'b1;

assign UART_RTS = 1'b0;
assign UART_TXD = 1'b1;
assign UART_DTR = 1'b1;

assign USER_OUT = 6'b000000;

endmodule
