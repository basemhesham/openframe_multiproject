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
    // ============================================================

    // Safe defaults: all pads configured as inputs (oeb=1) driving zero.
    // Even if accidentally enabled, outputs are low — no floating or
    // contention risk. dm=3'b110 (strong push-pull) is chosen so that
    // when a project IS selected, its pads are ready for digital I/O
    // without needing to reconfigure dm via the scan chain.
	    // ================================================================
    // Interconnect Wires
    // ================================================================
    wire mst_scl_i, mst_scl_o, mst_scl_t;
    wire mst_sda_i, mst_sda_o, mst_sda_t;
   
    wire slv_scl_i;
    wire slv_sda_i, slv_sda_o, slv_sda_t;
   
    wire uart_tx_pin;

    // ================================================================
    // GPIO Pin Mapping (Using Top GPIOs 0 to 4)
    // ================================================================
   
    // Inputs (from pad to core)
    assign mst_scl_i = gpio_top_in[0];
    assign mst_sda_i = gpio_top_in[1];
    assign slv_scl_i = gpio_top_in[2];
    assign slv_sda_i = gpio_top_in[3];
    // gpio_top_in[4] is unused (UART is TX only)

    // Outputs (from core to pad)
    assign gpio_top_out = {
        9'b0,         // [13:5] Unused outputs driven low
        uart_tx_pin,  // [4]    UART TX
        slv_sda_o,    // [3]    Slave SDA out
        1'b0,         // [2]    Slave SCL is input-only in chip_top, drive 0
        mst_sda_o,    // [1]    Master SDA out
        mst_scl_o     // [0]    Master SCL out
    };

    // Output Enable Bar (OEB) - Active Low (0 = Output, 1 = Input/Hi-Z)
    // Assuming `_t` signals from your I2C IP act as standard active-high Tri-state
    // (1 = high impedance, 0 = drive). If your IP uses active-low enable, invert these!
    assign gpio_top_oeb = {
        9'b1,         // [13:5] Unused pads configured as inputs (safe state)
        1'b0,         // [4]    UART TX is always an output (enable = 0)
        slv_sda_t,    // [3]    Slave SDA tri-state control
        1'b1,         // [2]    Slave SCL is input-only (disable output = 1)
        mst_sda_t,    // [1]    Master SDA tri-state control
        mst_scl_t     // [0]    Master SCL tri-state control
    };

    // ================================================================
    // Safe Defaults for Unused Banks
    // ================================================================
   
    // Bottom: 15 GPIOs, all input
    assign gpio_bot_out = 15'b0;
    assign gpio_bot_oeb = {15{1'b1}};

    // Right: 9 GPIOs, all input
    assign gpio_rt_out = 9'b0;
    assign gpio_rt_oeb = {9{1'b1}};

    // ================================================================
    // Drive Modes (dm) - Left as Strong Push-Pull (3'b110)
    // Note: I2C can emulate open-drain by holding output=0 and toggling OEB.
    // ================================================================
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

    // ================================================================
    // Instantiate chip_top
    // ================================================================
    chip_top #(
        .CLK_FREQ     (50_000_000),
        .I2C_FREQ     (400_000),
        .UART_BAUD    (115_200),
        .SLAVE_ADDR   (7'h55)
    ) u_chip_top (
        .clk          (clk),
        .rst_n        (reset_n),

        // I2C master bus
        .mst_scl_i    (mst_scl_i),
        .mst_scl_o    (mst_scl_o),
        .mst_scl_t    (mst_scl_t),
        .mst_sda_i    (mst_sda_i),
        .mst_sda_o    (mst_sda_o),
        .mst_sda_t    (mst_sda_t),

        // I2C slave bus
        .slv_scl_i    (slv_scl_i),
        .slv_sda_i    (slv_sda_i),
        .slv_sda_o    (slv_sda_o),
        .slv_sda_t    (slv_sda_t),

        // UART output
        .uart_tx_pin  (uart_tx_pin)
    );

endmodule