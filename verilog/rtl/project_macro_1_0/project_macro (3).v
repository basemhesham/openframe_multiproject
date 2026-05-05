// SPDX-License-Identifier: Apache-2.0
// project_macro — User design sandbox
//
// Port mapping by physical edge:
//   Left:   clk, reset_n (from green macro)
//   Bottom: 15 GPIOs (-> bottom orange -> Caravel right pads)
//   Right:  9 GPIOs  (-> right orange  -> Caravel top pads)
//   Top:    14 GPIOs  (-> top orange    -> Caravel left pads)
//
// Total usable GPIOs: 15 + 9 + 14 = 38
// All outputs have safe default tie-offs. Users replace them with their logic.
//
// GPIO Signal Reference:
//   gpio_*_out : Data driven onto the pad (active when oeb=0)
//   gpio_*_oeb : Output Enable Bar (0=output, 1=input/Hi-Z)
//   gpio_*_in  : Data sampled from the pad (always available)
//   gpio_*_dm  : Drive Mode, 3 bits per pad [dm2, dm1, dm0]
//
// Drive Mode (dm[2:0]) — Sky130 OpenFrame GPIO Pad Modes:
//   3'b000 : High-Z / Analog mode (pad completely disconnected)
//   3'b001 : Input only, no pull resistor
//   3'b010 : Input with weak pull-down (~50kΩ to VSS)
//   3'b011 : Input with weak pull-up   (~50kΩ to VDD)
//   3'b100 : Slow-slew output (reduced dI/dt for noise-sensitive signals)
//   3'b101 : Slow-slew output with open-drain (external pull-up required)
//   3'b110 : Strong digital push-pull output (DEFAULT — standard digital I/O)
//   3'b111 : Strong digital output with weak pull-up
//
// Note: oeb controls the output driver gate. dm configures the pad cell itself.
//   - For pure input:  oeb=1, dm=3'b001 (or 3'b010/011 for pull-down/up)
//   - For push-pull:   oeb=0, dm=3'b110
//   - For open-drain:  oeb=0, dm=3'b101 (needs external pull-up)
//   - For analog:      oeb=1, dm=3'b000 (bypasses digital buffers entirely)

`default_nettype none

module project_macro (
`ifdef USE_POWER_PINS
    inout vccd1,
    inout vssd1,
`endif
    // From green macro (left edge)
    input  wire        clk,
    input  wire        reset_n,
    input  wire        por_n,

    // Bottom GPIOs (15) -> Caravel right pads via bottom orange chain
    input  wire [14:0] gpio_bot_in,
    output wire [14:0] gpio_bot_out,
    output wire [14:0] gpio_bot_oeb,
    output wire [44:0] gpio_bot_dm,

    // Right GPIOs (9) -> Caravel top pads via right orange chain
    input  wire [8:0]  gpio_rt_in,
    output wire [8:0]  gpio_rt_out,
    output wire [8:0]  gpio_rt_oeb,
    output wire [26:0] gpio_rt_dm,

    // Top GPIOs (14) -> Caravel left pads via top orange chain
    input  wire [13:0] gpio_top_in,
    output wire [13:0] gpio_top_out,
    output wire [13:0] gpio_top_oeb,
    output wire [41:0] gpio_top_dm
);

    // ============================================================
    // USER LOGIC GOES HERE — Replace the safe tie-offs below
    NTT_Top_Wrapper NTT_Top_Wrapper(
    `ifdef USE_POWER_PINS
        .vccd1(vccd1),
        .vssd1(vssd1),
    `endif
        .clk(clk),
        .rst_n(reset_n),
        .cs_n(gpio_bot_in[0]),
        .mosi(gpio_bot_in[1]),
        .miso(gpio_bot_out[0])
    );
    // ============================================================

    // Safe defaults: all pads configured as inputs (oeb=1) driving zero.
    // Even if accidentally enabled, outputs are low — no floating or
    // contention risk. dm=3'b110 (strong push-pull) is chosen so that
    // when a project IS selected, its pads are ready for digital I/O
    // without needing to reconfigure dm via the scan chain.

    // Bottom: 15 GPIOs, all input
    assign gpio_bot_out[14:1] = 15'b0;

    assign gpio_bot_oeb[0] = 1'b0;
    assign gpio_bot_oeb[14:1] = {14{1'b1}};

    // Right: 9 GPIOs, all input
    assign gpio_rt_out = 9'b0;
    assign gpio_rt_oeb = {9{1'b1}};

    // Top: 14 GPIOs, all input
    assign gpio_top_out = 14'b0;
    assign gpio_top_oeb = {14{1'b1}};

    // Drive mode: 3'b110 = strong digital push-pull (see mode table above)
    genvar i;
    generate
        for (i = 0; i < 15; i = i + 1) begin : gen_bot_dm
            assign gpio_bot_dm[i*3 +: 3] = 3'b110;
        end
        for (i = 0; i < 9; i = i + 1) begin : gen_rt_dm
            assign gpio_rt_dm[i*3 +: 3] = 3'b110;
        end
        for (i = 0; i < 14; i = i + 1) begin : gen_top_dm
            assign gpio_top_dm[i*3 +: 3] = 3'b110;
        end
    endgenerate

endmodule
