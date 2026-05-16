//==============================================================================
// Module: nc_ticker
// Description: Programmable Tick/Pulse Generator
//
// Copyright (c) 2020 nativechips.ai
// Author: Mohamed Shalan (shalan@nativechips.ai)
// License: Apache License 2.0
//
// Parameters:
//   W - Counter width (default: 8)
//
// Timing: Period = clk_div + 1 clock cycles when enabled
//==============================================================================

`timescale 1ns/1ps
`default_nettype none

module nc_ticker #(parameter W = 8) (
    input   wire            clk,
    input   wire            rst_n,
    input   wire            en,
    input   wire [W-1:0]    clk_div,
    output  wire            tick
);

    reg [W-1:0] counter;
    wire        counter_is_zero = (counter == {W{1'b0}});
    wire        tick_w;
    reg         tick_reg;

    always @(posedge clk or negedge rst_n)
        if (!rst_n)
            counter <= {W{1'b0}};
        else if (en)
            if (counter_is_zero)
                counter <= clk_div;
            else
                counter <= counter - 1'b1;

    assign tick_w = (clk_div == {W{1'b0}}) ? 1'b1 : counter_is_zero;

    always @(posedge clk or negedge rst_n)
        if (!rst_n)
            tick_reg <= 1'b0;
        else if (en)
            tick_reg <= tick_w;
        else
            tick_reg <= 1'b0;

    assign tick = tick_reg;

endmodule

`default_nettype wire
