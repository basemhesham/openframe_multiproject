// SPDX-License-Identifier: Apache-2.0
// clk_div — Configurable clock divider for frequency monitoring
//
// f_out = f_in / (2 × (div_ratio + 1))
// When en = 0 the output is held low and the counter resets.

`timescale 1ns / 1ps
`default_nettype none

module clk_div #(
    parameter WIDTH = 16
)(
    input  wire             clk_in,
    input  wire             rst_n,
    input  wire             en,
    input  wire [WIDTH-1:0] div_ratio,
    output wire             clk_out
);

    reg [WIDTH-1:0] cnt;
    reg             out_reg;

    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            cnt     <= {WIDTH{1'b0}};
            out_reg <= 1'b0;
        end else if (!en) begin
            cnt     <= {WIDTH{1'b0}};
            out_reg <= 1'b0;
        end else begin
            if (cnt >= div_ratio) begin
                cnt     <= {WIDTH{1'b0}};
                out_reg <= ~out_reg;
            end else begin
                cnt <= cnt + 1'b1;
            end
        end
    end

    assign clk_out = out_reg;

endmodule
