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
    // GPIO user interface
    // ============================================================
    //
    // gpio_rt[0]   input  spi_sclk
    // gpio_rt[1]   input  spi_cs_n
    // gpio_rt[2]   input  spi_mosi
    // gpio_rt[3]   output spi_miso/status stream
    // gpio_rt[4]   output alarm
    // gpio_rt[5]   output motion_active
    // gpio_rt[6]   output sound_active
    // gpio_rt[7]   output i2c_error
    // gpio_rt[8]   output fsm_state
    //
    // gpio_top[0]  input  ir_in
    // gpio_top[1]  input  ir_sample_valid
    // gpio_top[2]  bidir  mic_i2c_scl, open-drain
    // gpio_top[3]  bidir  mic_i2c_sda, open-drain
    // gpio_top[13:4] inputs reserved
    //
    // The bottom GPIO bank is unused and left as high-impedance inputs.

    wire macro_rst_n = reset_n & por_n;

    wire spi_sclk = gpio_rt_in[0];
    wire spi_cs_n = gpio_rt_in[1];
    wire spi_mosi = gpio_rt_in[2];

    wire mic_scl_release;
    wire mic_sda_release;
    wire motion_active;
    wire sound_active;
    wire i2c_error;
    wire alarm;
    wire fsm_state;

    access_control_top u_access_control_top (
        .clk             (clk),
        .rst_n           (macro_rst_n),
        .ir_in           (gpio_top_in[0]),
        .ir_sample_valid (gpio_top_in[1]),
        .mic_scl         (mic_scl_release),
        .mic_scl_in      (gpio_top_in[2]),
        .mic_sda         (mic_sda_release),
        .mic_sda_in      (gpio_top_in[3]),
        .motion_active   (motion_active),
        .sound_active    (sound_active),
        .i2c_error_out   (i2c_error),
        .alarm           (alarm),
        .fsm_state_out   (fsm_state)
    );

    wire [7:0] status_byte = {
        3'b000,
        fsm_state,
        i2c_error,
        sound_active,
        motion_active,
        alarm
    };

    reg [2:0] spi_sclk_sync;
    reg [2:0] spi_cs_n_sync;
    reg [1:0] spi_mosi_sync;
    reg [7:0] spi_cmd_shift;
    reg [7:0] spi_status_shift;
    reg [2:0] spi_bit_count;
    reg       spi_miso_r;

    wire spi_selected   = ~spi_cs_n_sync[2];
    wire spi_was_idle   = spi_cs_n_sync[2] & ~spi_cs_n_sync[1];
    wire spi_sclk_rise  = spi_selected & spi_sclk_sync[1] & ~spi_sclk_sync[2];
    wire spi_sclk_fall  = spi_selected & ~spi_sclk_sync[1] & spi_sclk_sync[2];
    wire spi_mosi_sampled = spi_mosi_sync[1];

    always @(posedge clk or negedge macro_rst_n) begin
        if (!macro_rst_n) begin
            spi_sclk_sync    <= 3'b000;
            spi_cs_n_sync    <= 3'b111;
            spi_mosi_sync    <= 2'b00;
            spi_cmd_shift    <= 8'd0;
            spi_status_shift <= 8'd0;
            spi_bit_count    <= 3'd0;
            spi_miso_r       <= 1'b0;
        end else begin
            spi_sclk_sync <= {spi_sclk_sync[1:0], spi_sclk};
            spi_cs_n_sync <= {spi_cs_n_sync[1:0], spi_cs_n};
            spi_mosi_sync <= {spi_mosi_sync[0], spi_mosi};

            if (spi_cs_n_sync[1]) begin
                spi_cmd_shift    <= 8'd0;
                spi_status_shift <= status_byte;
                spi_bit_count    <= 3'd0;
                spi_miso_r       <= status_byte[7];
            end else if (spi_was_idle) begin
                spi_cmd_shift    <= 8'd0;
                spi_status_shift <= status_byte;
                spi_bit_count    <= 3'd0;
                spi_miso_r       <= status_byte[7];
            end else if (spi_sclk_rise) begin
                spi_cmd_shift <= {spi_cmd_shift[6:0], spi_mosi_sampled};
                spi_bit_count <= spi_bit_count + 1'b1;
            end else if (spi_sclk_fall) begin
                spi_status_shift <= {spi_status_shift[6:0], 1'b0};
                spi_miso_r       <= spi_status_shift[6];
            end
        end
    end

    wire spi_miso = spi_miso_r;

    // Bottom: 15 GPIOs, unused inputs
    assign gpio_bot_out = 15'b0;
    assign gpio_bot_oeb = {15{1'b1}};

    // Right GPIO outputs: SPI/status interface.
    assign gpio_rt_out[0] = 1'b0;
    assign gpio_rt_out[1] = 1'b0;
    assign gpio_rt_out[2] = 1'b0;
    assign gpio_rt_out[3] = spi_miso;
    assign gpio_rt_out[4] = alarm;
    assign gpio_rt_out[5] = motion_active;
    assign gpio_rt_out[6] = sound_active;
    assign gpio_rt_out[7] = i2c_error;
    assign gpio_rt_out[8] = fsm_state;

    assign gpio_rt_oeb[0] = 1'b1; // spi_sclk input
    assign gpio_rt_oeb[1] = 1'b1; // spi_cs_n input
    assign gpio_rt_oeb[2] = 1'b1; // spi_mosi input
    assign gpio_rt_oeb[3] = spi_cs_n; // spi_miso output when selected, Hi-Z otherwise
    assign gpio_rt_oeb[4] = 1'b0; // alarm output
    assign gpio_rt_oeb[5] = 1'b0; // motion_active output
    assign gpio_rt_oeb[6] = 1'b0; // sound_active output
    assign gpio_rt_oeb[7] = 1'b0; // i2c_error output
    assign gpio_rt_oeb[8] = 1'b0; // fsm_state output

    // Top GPIO outputs. I2C outputs are open-drain: drive low only.
    assign gpio_top_out[0]  = 1'b0;
    assign gpio_top_out[1]  = 1'b0;
    assign gpio_top_out[2]  = 1'b0;
    assign gpio_top_out[3]  = 1'b0;
    assign gpio_top_out[13:4] = 10'b0;

    assign gpio_top_oeb[0]  = 1'b1; // ir_in input
    assign gpio_top_oeb[1]  = 1'b1; // ir_sample_valid input
    assign gpio_top_oeb[2]  = mic_scl_release; // I2C SCL open-drain release/drive-low
    assign gpio_top_oeb[3]  = mic_sda_release; // I2C SDA open-drain release/drive-low
    assign gpio_top_oeb[13:4] = {10{1'b1}}; // reserved inputs

    // Drive mode per pad.
    genvar i;
    generate
        for (i = 0; i < 15; i = i + 1) begin : gen_bot_dm
            assign gpio_bot_dm[i*3 +: 3] = 3'b001;
        end
        for (i = 0; i < 9; i = i + 1) begin : gen_rt_dm
            if (i == 0 || i == 1 || i == 2) begin : gen_rt_in_dm
                assign gpio_rt_dm[i*3 +: 3] = 3'b001;
            end else begin : gen_rt_out_dm
                assign gpio_rt_dm[i*3 +: 3] = 3'b110;
            end
        end
        for (i = 0; i < 14; i = i + 1) begin : gen_top_dm
            if (i == 2 || i == 3) begin : gen_top_i2c_dm
                assign gpio_top_dm[i*3 +: 3] = 3'b101;
            end else begin : gen_top_in_dm
                assign gpio_top_dm[i*3 +: 3] = 3'b001;
            end
        end
    endgenerate

endmodule
