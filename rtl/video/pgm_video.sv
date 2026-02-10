module pgm_video (
    input         clk,
    input         reset,
    
    output        hs,
    output        vs,
    output [7:0]  r,
    output [7:0]  g,
    output [7:0]  b,
    output        blank_n
);

// Standard VGA 640x480 @ 60Hz (Placeholder)
// PGM native resolution is likely 320x224 or similar

reg [9:0] h_cnt;
reg [9:0] v_cnt;

always @(posedge clk) begin
    if (reset) begin
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

assign hs = ~(h_cnt >= 656 && h_cnt < 752);
assign vs = ~(v_cnt >= 490 && v_cnt < 492);
assign blank_n = (h_cnt < 640 && v_cnt < 480);

// Basic red screen for visibility
assign r = blank_n ? 8'hFF : 8'h00;
assign g = 8'h00;
assign b = 8'h00;

endmodule
