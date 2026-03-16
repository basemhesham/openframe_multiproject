// SPDX-License-Identifier: Apache-2.0
// orange_macro — 2x1 cascaded GPIO multiplexer tile
//
// Always PADS=15. Placed on bottom, right, and top sides of each project.
// Physical shape: rectangular, 55 um short side, long side matches project edge.
// Identical RTL for all three orientations; pin metal layer differs in LEF.
//
// Chain directions:
//   Bottom oranges: L->R per row  -> Right Purple  (15 GPIOs -> Caravel right)
//   Right  oranges: B->T per col  -> Top Purple    (9 of 15 -> Caravel top)
//   Top    oranges: R->L per row  -> Left Purple   (14 of 15 -> Caravel left)
//
// Each GPIO has: gpio_in (1b), gpio_out (1b), gpio_oeb (1b), gpio_dm (3b)

`default_nettype none

module orange_macro #(
    parameter PADS = 15
)(
    // POR for internal scan node
    input  wire por_n,

    // Scan chain feedthrough
    input  wire scan_clk_in,
    input  wire scan_latch_in,
    input  wire scan_in,
    output wire scan_clk_out,
    output wire scan_latch_out,
    output wire scan_out,

    // Pad side (toward purple / next link closer to Caravel pads)
    input  wire [PADS-1:0]   pad_side_gpio_in,
    output wire [PADS-1:0]   pad_side_gpio_out,
    output wire [PADS-1:0]   pad_side_gpio_oeb,
    output wire [PADS*3-1:0] pad_side_gpio_dm,

    // Chain side (from previous link, further from pads)
    output wire [PADS-1:0]   chain_side_gpio_in,
    input  wire [PADS-1:0]   chain_side_gpio_out,
    input  wire [PADS-1:0]   chain_side_gpio_oeb,
    input  wire [PADS*3-1:0] chain_side_gpio_dm,

    // Local project side
    output wire [PADS-1:0]   local_proj_gpio_in,
    input  wire [PADS-1:0]   local_proj_gpio_out,
    input  wire [PADS-1:0]   local_proj_gpio_oeb,
    input  wire [PADS*3-1:0] local_proj_gpio_dm
);

    // 1-bit scan node: sel_local (1 = route local project, 0 = pass chain)
    wire sel_local;

    scan_macro_node #(.WIDTH(1)) u_node (
        .por_n          (por_n),
        .scan_clk_in    (scan_clk_in),
        .scan_latch_in  (scan_latch_in),
        .scan_in        (scan_in),
        .scan_clk_out   (scan_clk_out),
        .scan_latch_out (scan_latch_out),
        .scan_out       (scan_out),
        .ctrl_out       (sel_local)
    );

    // Inbound broadcast: pad input goes to both local project and chain predecessor
    tech_buf u_buf_in_local [PADS-1:0] (.A(pad_side_gpio_in), .X(local_proj_gpio_in));
    tech_buf u_buf_in_chain [PADS-1:0] (.A(pad_side_gpio_in), .X(chain_side_gpio_in));

    // Outbound 2x1 MUX: local project or chain pass-through
    wire [PADS-1:0]   mux_out = sel_local ? local_proj_gpio_out : chain_side_gpio_out;
    wire [PADS-1:0]   mux_oeb = sel_local ? local_proj_gpio_oeb : chain_side_gpio_oeb;
    wire [PADS*3-1:0] mux_dm  = sel_local ? local_proj_gpio_dm  : chain_side_gpio_dm;

    // Output buffers
    tech_buf u_buf_out [PADS-1:0]   (.A(mux_out), .X(pad_side_gpio_out));
    tech_buf u_buf_oeb [PADS-1:0]   (.A(mux_oeb), .X(pad_side_gpio_oeb));
    tech_buf u_buf_dm  [PADS*3-1:0] (.A(mux_dm),  .X(pad_side_gpio_dm));

endmodule
