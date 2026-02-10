module dpram #(parameter ADDR_WIDTH=9, parameter DATA_WIDTH=10) (
    input  clk,
    input  we,
    input  [ADDR_WIDTH-1:0] wa,
    input  [DATA_WIDTH-1:0] wd,
    input  [ADDR_WIDTH-1:0] ra,
    output reg [DATA_WIDTH-1:0] rd
);
    reg [DATA_WIDTH-1:0] ram [0:(2**ADDR_WIDTH)-1] /* synthesis syn_ramstyle = "no_rw_check, M10K" */;
    always @(posedge clk) begin
        if (we) ram[wa] <= wd;
        rd <= ram[ra];
    end
endmodule
