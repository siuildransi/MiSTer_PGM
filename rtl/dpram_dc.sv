// Dual-clock True Dual-Port RAM
// Puerto A: lectura/escritura (reloj A)
// Puerto B: solo lectura (reloj B)
// Garantiza inferencia M10K en Cyclone V
module dpram_dc #(parameter ADDR_WIDTH=16, parameter DATA_WIDTH=8) (
    // Puerto A (CPU)
    input                       clk_a,
    input                       we_a,
    input  [ADDR_WIDTH-1:0]     addr_a,
    input  [DATA_WIDTH-1:0]     din_a,
    output reg [DATA_WIDTH-1:0] dout_a,

    // Puerto B (Z80 / Audio)
    input                       clk_b,
    input                       we_b,
    input  [ADDR_WIDTH-1:0]     addr_b,
    input  [DATA_WIDTH-1:0]     din_b,
    output reg [DATA_WIDTH-1:0] dout_b
);
    reg [DATA_WIDTH-1:0] ram [0:(2**ADDR_WIDTH)-1] /* synthesis syn_ramstyle = "no_rw_check, M10K" */;

    // Puerto A
    always @(posedge clk_a) begin
        if (we_a) ram[addr_a] <= din_a;
        dout_a <= ram[addr_a];
    end

    // Puerto B
    always @(posedge clk_b) begin
        if (we_b) ram[addr_b] <= din_b;
        dout_b <= ram[addr_b];
    end
endmodule
