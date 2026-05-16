// SPDX-License-Identifier: Apache-2.0
// fll_top — Wrapper around fracn_dll with /2 divider for 48 MHz USB clock
//
// The FLL ring oscillator runs at 96 MHz (from 6-12 MHz xclk reference).
// A /2 toggle flip-flop produces a clean 48 MHz clock for usb CDC.
// The undivided FLL output is also available for monitoring.

`timescale 1ns / 1ps
`default_nettype none

module fll_top (
`ifdef USE_POWER_PINS
    inout  VPWR,
    inout  VGND,
`endif
    input  wire        resetb,
    input  wire        enable,
    input  wire        osc_ref,
    input  wire [7:0]  div,
    input  wire        dco,
    input  wire [25:0] ext_trim,
    output wire        clk_96m,
    output wire        clk_48m
);

    wire [1:0] fll_clk_out;

    dll u_dll (
`ifdef USE_POWER_PINS
        .VPWR(VPWR),
        .VGND(VGND),
`endif
        .resetb   (resetb),
        .enable   (enable),
        .osc      (osc_ref),
        .clockp   (fll_clk_out),
        .div      (div),
        .dco      (dco),
        .ext_trim (ext_trim)
    );

    assign clk_96m = fll_clk_out[0];

    reg div2;
    always @(posedge fll_clk_out[0] or negedge resetb) begin
        if (!resetb)
            div2 <= 1'b0;
        else
            div2 <= ~div2;
    end

    assign clk_48m = div2;

endmodule
