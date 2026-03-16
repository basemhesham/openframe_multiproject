// SPDX-License-Identifier: Apache-2.0
// green_macro — Per-project clock gating and reset isolation tile
//
// Placed to the LEFT of each project macro (45 um wide).
// Contains a 1-bit scan node controlling project enable.
// Daisy-chains sys_clk and sys_reset_n vertically (bottom to top) within
// each column of the grid.

`default_nettype none

module green_macro (
    // System clock/reset column chain (bottom to top)
    input  wire sys_clk_in,
    input  wire sys_reset_n_in,
    output wire sys_clk_out,
    output wire sys_reset_n_out,

    // Gated outputs to the project macro (left edge)
    output wire proj_clk_out,
    output wire proj_reset_n_out,
    output wire proj_por_n_out,

    // POR for internal scan node
    input  wire por_n,

    // Scan chain feedthrough
    input  wire scan_clk_in,
    input  wire scan_latch_in,
    input  wire scan_in,
    output wire scan_clk_out,
    output wire scan_latch_out,
    output wire scan_out
);

    // 1-bit scan node: proj_en
    wire proj_en;

    scan_macro_node #(.WIDTH(1)) u_node (
        .por_n          (por_n),
        .scan_clk_in    (scan_clk_in),
        .scan_latch_in  (scan_latch_in),
        .scan_in        (scan_in),
        .scan_clk_out   (scan_clk_out),
        .scan_latch_out (scan_latch_out),
        .scan_out       (scan_out),
        .ctrl_out       (proj_en)
    );

    // Buffer sys_clk and sys_reset_n upward to next green in column
    tech_clkbuf u_clk_rep (.A(sys_clk_in),    .X(sys_clk_out));
    tech_buf    u_rst_rep (.A(sys_reset_n_in), .X(sys_reset_n_out));

    // Project reset: held low when project is disabled
    wire rst_and_out = sys_reset_n_in & proj_en;
    tech_buf u_rst_drv (.A(rst_and_out), .X(proj_reset_n_out));

    // Glitch-free clock gating via ICG cell
    tech_clkgate u_icg (.CLK(sys_clk_in), .GATE(proj_en), .GCLK(proj_clk_out));

    // Buffer POR to project macro
    tech_buf u_por_drv (.A(por_n), .X(proj_por_n_out));

endmodule
