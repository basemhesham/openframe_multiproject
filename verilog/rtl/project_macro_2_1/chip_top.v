// =============================================================================
// chip_top.v  — updated top level: PID replaces FSM, PWM actuator added
// =============================================================================
// Sensor  : Any I2C sensor at configurable address (default TMP117 @ 0x48)
//           Read by i2c_master_seq.v — returns 16-bit raw word
// Actuator: Any PWM-compatible device (fan, servo, heater, motor, LED)
//           Driven by pwm_gen.v output on pwm_out pad
// Control : pid_controller.v — fixed-point P+I+D, Q8.8 arithmetic
//           Setpoint and gains runtime-configurable via I2C slave
//
// Pad assignment:
//   mst_scl_i/o/t  — I2C master bus SCL (to sensor)
//   mst_sda_i/o/t  — I2C master bus SDA (to sensor)
//   slv_scl_i       — I2C slave bus SCL  (from host MCU)
//   slv_sda_i/o/t  — I2C slave bus SDA  (from host MCU)
//   pwm_out         — PWM signal → MOSFET gate → actuator
//   uart_tx_pin     — 115200 8N1 serial output → PC/terminal
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module chip_top #(
    // ── Clock & interface parameters ──────────────────────────────────
    parameter CLK_FREQ    = 50_000_000,  // system clock Hz
    parameter I2C_FREQ    = 400_000,     // I2C SCL Hz (400 kHz Fast Mode)
    parameter UART_BAUD   = 115_200,     // UART baud rate

    // ── I2C addresses ─────────────────────────────────────────────────
    parameter SENSOR_ADDR = 7'h48,       // I2C sensor address (TMP117 default)
    parameter SLAVE_ADDR  = 7'h55,       // This chip's own I2C slave address

    // ── PID parameters ────────────────────────────────────────────────
    parameter PID_SAMPLE_HZ  = 10,       // PID update rate in Hz
    parameter SENSOR_SCALE   = 1,        // Raw→Q8.8 shift: 1 for TMP117, 0 for others

    // ── Default PID gains (Q8.8) — overridable via I2C at runtime ─────
    parameter DEFAULT_SETPT  = 16'h1900, // 25.0°C in Q8.8
    parameter DEFAULT_KP     = 16'h0100, // Kp = 1.0
    parameter DEFAULT_KI     = 16'h0040, // Ki = 0.25
    parameter DEFAULT_KD     = 16'h0000  // Kd = 0.0 (disabled)
)(
    input  wire clk,
    input  wire rst_n,             // active-low reset from pad

    // ── I2C master bus (sensor side) ──────────────────────────────────
    input  wire mst_scl_i,
    output wire mst_scl_o,
    output wire mst_scl_t,         // tristate enable: 0=drive, 1=Hi-Z
    input  wire mst_sda_i,
    output wire mst_sda_o,
    output wire mst_sda_t,

    // ── I2C slave bus (host MCU side) ─────────────────────────────────
    input  wire slv_scl_i,
    input  wire slv_sda_i,
    output wire slv_sda_o,
    output wire slv_sda_t,

    // ── PWM output → MOSFET → actuator ────────────────────────────────
    output wire pwm_out,

    // ── UART serial output → PC / terminal ────────────────────────────
    output wire uart_tx_pin
);

    wire rst = ~rst_n;

    // =========================================================================
    // Internal wires
    // =========================================================================

    // Sensor data from I2C master
    wire [15:0] sensor_raw;
    wire        sensor_valid;

    // Config bytes from I2C slave
    wire [7:0]  slv_rx_data;
    wire        slv_rx_valid;

    // PID → PWM
    wire [7:0]  duty;

    // PID → UART
    wire [7:0]  uart_data;
    wire        uart_valid;
    wire        uart_ready;

    // =========================================================================
    // I2C Master Sequencer
    // Polls the sensor at each wait cycle, returns 16-bit raw reading.
    // actuator_cmd and actuator_valid are tied off — actuation is now via PWM.
    // =========================================================================
    i2c_master_seq #(
        .CLK_FREQ      (CLK_FREQ),
        .I2C_FREQ      (I2C_FREQ),
        .SENSOR_ADDR   (SENSOR_ADDR),
        .ACTUATOR_ADDR (SENSOR_ADDR)   // unused — PWM handles actuation
    ) u_master_seq (
        .clk            (clk),
        .rst            (rst),

        .scl_i          (mst_scl_i),
        .scl_o          (mst_scl_o),
        .scl_t          (mst_scl_t),
        .sda_i          (mst_sda_i),
        .sda_o          (mst_sda_o),
        .sda_t          (mst_sda_t),

        .sensor_data    (sensor_raw),
        .sensor_valid   (sensor_valid),

        // Actuator I2C write disabled — tie off
        .actuator_cmd   (8'h00),
        .actuator_valid (1'b0)
    );

    // =========================================================================
    // I2C Slave
    // Host MCU writes 6-byte config: [setpoint_H, setpoint_L, Kp_H, Kp_L, Ki_H, Ki_L]
    // =========================================================================
    i2c_slave #(
        .FILTER_LEN (4)
    ) u_slave (
        .clk                 (clk),
        .rst                 (rst),

        .scl_i               (slv_scl_i),
        .sda_i               (slv_sda_i),
        .sda_o               (slv_sda_o),
        .sda_t               (slv_sda_t),

        .device_address      (SLAVE_ADDR),
        .device_address_mask (7'h7F),
        .enable              (1'b1),

        // Receive path → PID config
        .m_axis_data_tdata   (slv_rx_data),
        .m_axis_data_tvalid  (slv_rx_valid),
        .m_axis_data_tready  (1'b1),        // always accept config bytes
        .m_axis_data_tlast   (),

        // Transmit path — not used (slave read-only in this design)
        .s_axis_data_tdata   (8'h00),
        .s_axis_data_tvalid  (1'b0),
        .s_axis_data_tready  ()
    );

    // =========================================================================
    // PID Controller
    // Reads sensor_raw, computes duty, streams UART frames
    // =========================================================================
    pid_controller #(
        .CLK_FREQ       (CLK_FREQ),
        .SAMPLE_HZ      (PID_SAMPLE_HZ),
        .SENSOR_SCALE   (SENSOR_SCALE),
        .DEFAULT_SETPT  (DEFAULT_SETPT),
        .DEFAULT_KP     (DEFAULT_KP),
        .DEFAULT_KI     (DEFAULT_KI),
        .DEFAULT_KD     (DEFAULT_KD)
    ) u_pid (
        .clk          (clk),
        .rst          (rst),

        // Sensor input
        .sensor_raw   (sensor_raw),
        .sensor_valid (sensor_valid),

        // Runtime config from I2C slave
        .cfg_byte     (slv_rx_data),
        .cfg_valid    (slv_rx_valid),

        // PWM duty output
        .duty         (duty),

        // UART frame output
        .uart_data    (uart_data),
        .uart_valid   (uart_valid),
        .uart_ready   (uart_ready)
    );

    // =========================================================================
    // PWM Generator → MOSFET Gate → Actuator
    // 8-bit resolution, ~195 kHz at 50 MHz (above audible range)
    // =========================================================================
    pwm_gen #(
        .CLK_FREQ    (CLK_FREQ),
        .RESOLUTION  (8),
        .ACTIVE_HIGH (1)
    ) u_pwm (
        .clk     (clk),
        .rst     (rst),
        .duty    (duty),
        .pwm_out (pwm_out)
    );

    // =========================================================================
    // UART Transmitter
    // 8N1, 115200 baud, outputs 7-byte PID telemetry frame
    // =========================================================================
    uart_tx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (UART_BAUD)
    ) u_uart (
        .clk   (clk),
        .rst   (rst),
        .data  (uart_data),
        .valid (uart_valid),
        .ready (uart_ready),
        .tx    (uart_tx_pin)
    );

endmodule
`default_nettype wire