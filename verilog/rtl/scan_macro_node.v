// SPDX-License-Identifier: Apache-2.0
// scan_macro_node — Parameterized shift register with shadow latch
//
// Instantiated inside every green, orange, and purple macro.
// WIDTH=1 for green/orange, WIDTH=1+ceil(log2(PORTS)) for purple.
//
// Shadow register is reset by por_n only (not sys_reset_n) to guarantee
// safe power-up state while preserving scan configuration across system resets.
// Shift register has no reset; the scan chain is locked on POR so no
// clocks or latches can reach it until the magic word is provided.

`default_nettype none

module scan_macro_node #(
    parameter WIDTH = 1
)(
    input  wire             por_n,
    input  wire             scan_clk_in,
    input  wire             scan_latch_in,
    input  wire             scan_in,
    output wire             scan_clk_out,
    output wire             scan_latch_out,
    output wire             scan_out,
    output wire [WIDTH-1:0] ctrl_out
);

    // Repeater buffers for signal integrity across the chip
    tech_clkbuf u_sclk_buf (.A(scan_clk_in),   .X(scan_clk_out));
    tech_buf    u_slat_buf (.A(scan_latch_in),  .X(scan_latch_out));

    // Shift register (no reset needed — chain is locked on POR)
    reg [WIDTH-1:0] shift_reg;

    generate
        if (WIDTH == 1) begin : gen_w1
            always @(posedge scan_clk_in) begin
                shift_reg <= scan_in;
            end
        end else begin : gen_wn
            always @(posedge scan_clk_in) begin
                shift_reg <= {shift_reg[WIDTH-2:0], scan_in};
            end
        end
    endgenerate

    assign scan_out = shift_reg[WIDTH-1];

    // Shadow register: captures shift_reg on scan_latch_in assertion.
    // Reset by POR only — config survives system resets.
    reg [WIDTH-1:0] shadow_reg;

    always @(posedge scan_clk_in or negedge por_n) begin
        if (!por_n)
            shadow_reg <= {WIDTH{1'b0}};
        else if (scan_latch_in)
            shadow_reg <= shift_reg;
    end

    assign ctrl_out = shadow_reg;

endmodule
