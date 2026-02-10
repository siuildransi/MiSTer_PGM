// PLL for PGM MiSTer Core
// Generates video clock from 50MHz reference.
// Uses altera_pll which is a built-in Quartus synthesis primitive.

`timescale 1 ps / 1 ps

module pll (
    input  wire refclk,    // 50 MHz reference clock
    input  wire rst,       // Reset
    output wire outclk_0,  // ~25 MHz video clock
    output wire locked     // PLL locked indicator
);

altera_pll #(
    .fractional_vco_multiplier("false"),
    .reference_clock_frequency("50.0 MHz"),
    .operation_mode("direct"),
    .number_of_clocks(1),
    .output_clock_frequency0("25.175000 MHz"),
    .phase_shift0("0 ps"),
    .duty_cycle0(50),
    .output_clock_frequency1("0 MHz"),
    .phase_shift1("0 ps"),
    .duty_cycle1(50),
    .output_clock_frequency2("0 MHz"),
    .phase_shift2("0 ps"),
    .duty_cycle2(50),
    .output_clock_frequency3("0 MHz"),
    .phase_shift3("0 ps"),
    .duty_cycle3(50),
    .output_clock_frequency4("0 MHz"),
    .phase_shift4("0 ps"),
    .duty_cycle4(50),
    .output_clock_frequency5("0 MHz"),
    .phase_shift5("0 ps"),
    .duty_cycle5(50),
    .output_clock_frequency6("0 MHz"),
    .phase_shift6("0 ps"),
    .duty_cycle6(50),
    .output_clock_frequency7("0 MHz"),
    .phase_shift7("0 ps"),
    .duty_cycle7(50),
    .output_clock_frequency8("0 MHz"),
    .phase_shift8("0 ps"),
    .duty_cycle8(50),
    .pll_type("General"),
    .pll_subtype("General")
) altera_pll_i (
    .rst(rst),
    .outclk({outclk_0}),
    .locked(locked),
    .fboutclk(),
    .fbclk(1'b0),
    .refclk(refclk)
);

endmodule
