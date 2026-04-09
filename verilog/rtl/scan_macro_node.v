// SPDX-License-Identifier: Apache-2.0
// scan_macro_node — Parameterized shift register with shadow latch
//
// Instantiated inside every green, orange, and purple macro.
// WIDTH=1 for green/orange, WIDTH=1+ceil(log2(PORTS)) for purple.
//
// Dual-sided scan ports: both sides (a and b) carry scan_in, scan_out,
// scan_clk, and scan_latch. The wrapper picks the direction by connecting
// the appropriate side's in/out. Internally:
//   - scan_in:  OR of scan_in_a and scan_in_b (only one driven, other tied 0)
//   - scan_out: fanned out to both scan_out_a and scan_out_b
//   - scan_clk/scan_latch: OR'd inputs, buffered to both outputs
//
// Shadow register is reset by por_n only (not sys_reset_n) to guarantee
// safe power-up state while preserving scan configuration across system resets.
// Shift register has no reset; the scan chain is locked on POR so no
// clocks or latches can reach it until the magic word is provided.

`default_nettype none

module scan_macro_node #(
    parameter WIDTH = 1
)(
`ifdef USE_POWER_PINS
    inout vccd1,
    inout vssd1,
`endif
    input  wire             por_n,

    // Side A scan ports
    input  wire             scan_clk_a,
    input  wire             scan_latch_a,
    input  wire             scan_in_a,
    output wire             scan_clk_out_a,
    output wire             scan_latch_out_a,
    output wire             scan_out_a,

    // Side B scan ports
    input  wire             scan_clk_b,
    input  wire             scan_latch_b,
    input  wire             scan_in_b,
    output wire             scan_clk_out_b,
    output wire             scan_latch_out_b,
    output wire             scan_out_b,

    output wire [WIDTH-1:0] ctrl_out
);

    // Merge inputs from both sides (only one side driven, other tied to 0)
    wire scan_clk_merged   = scan_clk_a   | scan_clk_b;
    wire scan_latch_merged = scan_latch_a  | scan_latch_b;
    wire scan_in_merged    = scan_in_a     | scan_in_b;

    // Repeater buffers for signal integrity — fan out to both sides
    tech_clkbuf u_sclk_buf_a (.A(scan_clk_merged),   .X(scan_clk_out_a));
    tech_clkbuf u_sclk_buf_b (.A(scan_clk_merged),   .X(scan_clk_out_b));
    tech_buf    u_slat_buf_a (.A(scan_latch_merged),  .X(scan_latch_out_a));
    tech_buf    u_slat_buf_b (.A(scan_latch_merged),  .X(scan_latch_out_b));

    // Shift register (no reset needed — chain is locked on POR)
    reg [WIDTH-1:0] shift_reg;

    generate
        if (WIDTH == 1) begin : gen_w1
            always @(posedge scan_clk_merged) begin
                shift_reg <= scan_in_merged;
            end
        end else begin : gen_wn
            always @(posedge scan_clk_merged) begin
                shift_reg <= {shift_reg[WIDTH-2:0], scan_in_merged};
            end
        end
    endgenerate

    wire scan_out_int = shift_reg[WIDTH-1];

    // Fan out scan_out to both sides
    tech_buf u_sout_buf_a (.A(scan_out_int), .X(scan_out_a));
    tech_buf u_sout_buf_b (.A(scan_out_int), .X(scan_out_b));

    // Shadow register: captures shift_reg on scan_latch assertion.
    // Reset by POR only — config survives system resets.
    reg [WIDTH-1:0] shadow_reg;

    always @(posedge scan_clk_merged or negedge por_n) begin
        if (!por_n)
            shadow_reg <= {WIDTH{1'b0}};
        else if (scan_latch_merged)
            shadow_reg <= shift_reg;
    end

    assign ctrl_out = shadow_reg;

endmodule
