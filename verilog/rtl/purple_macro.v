// SPDX-License-Identifier: Apache-2.0
// purple_macro — Root GPIO aggregator at chip edge
//
// Always PADS=15. Placed at right, top, and left chip edges (50 um thick).
// Selects one of PORTS incoming orange chain endpoints to connect to Caravel pads.
// Master enable safety bit forces all outputs to Hi-Z when deasserted.
//
// Instances:
//   Right Purple:  PORTS=ROWS, all 15 bits -> Caravel gpio[14:0]
//   Top Purple:    PORTS=COLS, lower 9 of 15 -> Caravel gpio[23:15]
//   Left Purple:   PORTS=ROWS, lower 14 of 15 -> Caravel gpio[37:24]
//
// Scan bits: 1 (master_en) + ceil(log2(PORTS)) (port_sel)

`default_nettype none

module purple_macro #(
    parameter PADS  = 15,
    parameter PORTS = 3
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

    // Pad side (to Caravel GPIOs)
    input  wire [PADS-1:0]   pad_gpio_in,
    output wire [PADS-1:0]   pad_gpio_out,
    output wire [PADS-1:0]   pad_gpio_oeb,
    output wire [PADS*3-1:0] pad_gpio_dm,

    // Orange tree side (from chain endpoints)
    output wire [PORTS*PADS-1:0]   tree_gpio_in,
    input  wire [PORTS*PADS-1:0]   tree_gpio_out,
    input  wire [PORTS*PADS-1:0]   tree_gpio_oeb,
    input  wire [PORTS*PADS*3-1:0] tree_gpio_dm
);

    // Scan node width: 1 (master_en) + ceil(log2(PORTS)) (port_sel)
    localparam SEL_BITS   = (PORTS > 1) ? $clog2(PORTS) : 1;
    localparam SCAN_WIDTH = 1 + SEL_BITS;

    wire [SCAN_WIDTH-1:0] scan_ctrl;
    wire                  master_en = scan_ctrl[SCAN_WIDTH-1];
    wire [SEL_BITS-1:0]   port_sel  = scan_ctrl[SEL_BITS-1:0];

    scan_macro_node #(.WIDTH(SCAN_WIDTH)) u_node (
        .por_n          (por_n),
        .scan_clk_in    (scan_clk_in),
        .scan_latch_in  (scan_latch_in),
        .scan_in        (scan_in),
        .scan_clk_out   (scan_clk_out),
        .scan_latch_out (scan_latch_out),
        .scan_out       (scan_out),
        .ctrl_out       (scan_ctrl)
    );

    // Inbound broadcast: buffer pad input and fan out to all chain ports
    wire [PADS-1:0] buf_pad_in;
    tech_buf u_buf_in [PADS-1:0] (.A(pad_gpio_in), .X(buf_pad_in));

    genvar i;
    generate
        for (i = 0; i < PORTS; i = i + 1) begin : gen_fan
            assign tree_gpio_in[i*PADS +: PADS] = buf_pad_in;
        end
    endgenerate

    // Outbound MUX: select one port (clamp port_sel to valid range)
    wire [SEL_BITS-1:0] safe_sel = (port_sel < PORTS) ? port_sel : {SEL_BITS{1'b0}};

    wire [PADS-1:0]   mux_out = tree_gpio_out [safe_sel * PADS     +: PADS];
    wire [PADS-1:0]   mux_oeb = tree_gpio_oeb [safe_sel * PADS     +: PADS];
    wire [PADS*3-1:0] mux_dm  = tree_gpio_dm  [safe_sel * (PADS*3) +: (PADS*3)];

    // Master enable: force Hi-Z when disabled
    wire [PADS-1:0]   safe_out = master_en ? mux_out : {PADS{1'b0}};
    wire [PADS-1:0]   safe_oeb = master_en ? mux_oeb : {PADS{1'b1}};
    wire [PADS*3-1:0] safe_dm  = master_en ? mux_dm  : {(PADS*3){1'b0}};

    // Output buffers
    tech_buf u_buf_out [PADS-1:0]   (.A(safe_out), .X(pad_gpio_out));
    tech_buf u_buf_oeb [PADS-1:0]   (.A(safe_oeb), .X(pad_gpio_oeb));
    tech_buf u_buf_dm  [PADS*3-1:0] (.A(safe_dm),  .X(pad_gpio_dm));

endmodule
