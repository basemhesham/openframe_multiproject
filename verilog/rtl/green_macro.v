// SPDX-License-Identifier: Apache-2.0
// green_macro — Per-project clock gating and reset isolation tile
//
// Placed to the LEFT of each project macro (45 um wide).
// Contains a 1-bit scan node controlling project enable.
// Daisy-chains sys_clk and sys_reset_n vertically (bottom to top) within
// each column of the grid.
//
// Scan ports on both short sides (#S and #N). The wrapper picks direction:
//   - Bottom-to-top chain: scan_in from #S, scan_out from #N
//   - Top-to-bottom chain: scan_in from #N, scan_out from #S

`default_nettype none

module green_macro (
`ifdef USE_POWER_PINS
    inout vccd1,
    inout vssd1,
`endif
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

    // Scan chain — South side (#S)
    input  wire scan_clk_s,
    input  wire scan_latch_s,
    input  wire scan_in_s,
    output wire scan_clk_out_s,
    output wire scan_latch_out_s,
    output wire scan_out_s,

    // Scan chain — North side (#N)
    input  wire scan_clk_n,
    input  wire scan_latch_n,
    input  wire scan_in_n,
    output wire scan_clk_out_n,
    output wire scan_latch_out_n,
    output wire scan_out_n
);

    // 1-bit scan node: proj_en
    wire proj_en;

    scan_macro_node #(.WIDTH(1)) u_node (
        .por_n           (por_n),
        .scan_clk_a      (scan_clk_s),
        .scan_latch_a    (scan_latch_s),
        .scan_in_a       (scan_in_s),
        .scan_clk_out_a  (scan_clk_out_s),
        .scan_latch_out_a(scan_latch_out_s),
        .scan_out_a      (scan_out_s),
        .scan_clk_b      (scan_clk_n),
        .scan_latch_b    (scan_latch_n),
        .scan_in_b       (scan_in_n),
        .scan_clk_out_b  (scan_clk_out_n),
        .scan_latch_out_b(scan_latch_out_n),
        .scan_out_b      (scan_out_n),
        .ctrl_out        (proj_en)
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
