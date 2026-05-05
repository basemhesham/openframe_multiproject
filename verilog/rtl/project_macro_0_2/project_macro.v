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

// SPDX-License-Identifier: Apache-2.0
// project_macro — User design sandbox
//
// Port mapping by physical edge:
//   Left:   clk, reset_n (from green macro)
//   Bottom: 15 GPIOs (-> bottom orange -> Caravel right pads)
//   Right:  9 GPIOs  (-> right orange  -> Caravel top pads)
//   Top:    14 GPIOs  (-> top orange    -> Caravel left pads)

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
    // USER LOGIC: TraceGuard-X (8-States, 1mm2 Optimized)
    // ============================================================

    // 1. Internal Wires for Core Outputs
    wire       trace_tx;
    wire       trace_alert;
    wire       trace_match;
    wire       trace_busy;
    wire       trace_ready;
    wire       trace_overflow;
    wire       trace_wd_alert;
    wire [1:0] trace_mode;
    wire [7:0] trace_score;

    // 2. Core Instantiation
    traceguard_x #(
        .TOP_CLK_FREQ(25_000_000),
        .TOP_BAUD_RATE(115_200),
        .TOP_WATCHDOG_CYCLES(25_000_000)
    ) my_core (
        .clk(clk),
        .rst_n(reset_n),
        .uart_rx(gpio_bot_in[0]),    // RX on Bottom Pad 0
        .uart_tx(trace_tx),
        .gpio_alert(trace_alert),
        .gpio_match(trace_match),
        .gpio_busy(trace_busy),
        .gpio_ready(trace_ready),
        .gpio_overflow(trace_overflow),
        .gpio_wd_alert(trace_wd_alert),
        .gpio_mode(trace_mode),
        .gpio_score(trace_score)
    );

    // 3. GPIO Routing & Output Enable Control
    // -------------------------------------------------------------
    // OEB Rules: 0 = Output, 1 = Input
    // -------------------------------------------------------------
    
    // Bottom Edge: 
    // [14:10] Unused Inputs
    // [9:8]   gpio_mode (Outputs)
    // [7]     gpio_wd_alert (Output)
    // [6]     gpio_overflow (Output)
    // [5]     gpio_ready (Output)
    // [4]     gpio_busy (Output)
    // [3]     gpio_match (Output)
    // [2]     gpio_alert (Output)
    // [1]     uart_tx (Output)
    // [0]     uart_rx (Input)
    assign gpio_bot_out = {5'd0, trace_mode, trace_wd_alert, trace_overflow, trace_ready, trace_busy, trace_match, trace_alert, trace_tx, 1'b0};
    assign gpio_bot_oeb = 15'b11111_00_0000000_1;

    // Right Edge:
    // [8]   Unused Input
    // [7:0] gpio_score (Outputs) -> Full contiguous byte!
    assign gpio_rt_out = {1'b0, trace_score};
    assign gpio_rt_oeb = 9'b1_0000_0000;

    // Top Edge: (All 14 pins unused -> Set as Inputs)
    assign gpio_top_out = 14'd0;
    assign gpio_top_oeb = 14'h3FFF; // All 1s

    // 4. Drive Mode Configuration
    // 3'b110 = strong digital push-pull (DEFAULT)
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
