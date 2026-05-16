// SPDX-License-Identifier: Apache-2.0
// clk_mux_2to1 — Glitch-free 2:1 clock multiplexer
//
// Uses negedge-triggered double synchronizers so the gating signal
// only changes when the associated clock is LOW, preventing runt
// pulses on the output.
//
// sel = 0 → clk0   |   sel = 1 → clk1

`timescale 1ns / 1ps
`default_nettype none

module clk_mux_2to1 (
    input  wire clk0,
    input  wire clk1,
    input  wire sel,
    input  wire rst_n,
    output wire clk_out
);

    reg sel_meta0, sel_q0;
    always @(negedge clk0 or negedge rst_n) begin
        if (!rst_n) begin
            sel_meta0 <= 1'b0;
            sel_q0    <= 1'b0;
        end else begin
            sel_meta0 <= sel;
            sel_q0    <= sel_meta0;
        end
    end

    reg sel_meta1, sel_q1;
    always @(negedge clk1 or negedge rst_n) begin
        if (!rst_n) begin
            sel_meta1 <= 1'b0;
            sel_q1    <= 1'b0;
        end else begin
            sel_meta1 <= sel;
            sel_q1    <= sel_meta1;
        end
    end

    assign clk_out = (clk0 & ~sel_q1) | (clk1 & sel_q0);

endmodule
