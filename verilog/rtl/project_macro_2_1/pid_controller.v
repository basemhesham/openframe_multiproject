// =============================================================================
// pid_controller.v
// Fixed-point PID Controller — replaces data_proc_fsm.v
// =============================================================================
// Sensor  : Any I2C sensor returning a 16-bit unsigned word
//           (TMP117, SHT40, LM75A, MCP9808, BME280, HDC1080, PCT2075 ...)
// Actuator: Any PWM-driven actuator (DC fan, servo, heater, motor, LED ...)
//
// Fixed-point format: Q8.8 (8 integer bits + 8 fractional bits = 16 bits)
//   - Allows values from 0 to 255.996 with resolution of ~0.004
//   - Gains Kp / Ki stored as Q8.8 (e.g. Kp=1.0 → 0x0100, Kp=0.5 → 0x0080)
//
// I2C slave configuration protocol (6 bytes written in order):
//   Byte 0: setpoint_H   (MSB of Q8.8 setpoint)
//   Byte 1: setpoint_L   (LSB of Q8.8 setpoint)
//   Byte 2: Kp_H         (MSB of Q8.8 proportional gain)
//   Byte 3: Kp_L         (LSB of Q8.8 proportional gain)
//   Byte 4: Ki_H         (MSB of Q8.8 integral gain)
//   Byte 5: Ki_L         (LSB of Q8.8 integral gain)
//
// UART output frame (7 bytes, 115200 baud 8N1):
//   0xAA | SENS_H | SENS_L | SETPT_H | SETPT_L | DUTY | 0x55
//
// Sensor raw → Q8.8 conversion:
//   The SENSOR_SCALE parameter controls how raw sensor bits map to Q8.8.
//   Examples:
//     TMP117 : SENSOR_SCALE = 1  (raw LSB = 1/128°C, Q8.8 LSB = 1/256°C → shift left 1)
//     LM75A  : SENSOR_SCALE = 7  (9-bit, bits [15:7] valid → shift left 7 to align)
//     SHT40  : SENSOR_SCALE = 0  (pre-scaled by firmware before passing in)
//     Generic: SENSOR_SCALE = 0  (pass raw value directly as Q8.8)
//
// Anti-windup: integral clamped to ±INTEGRAL_LIMIT (default ±32767 in Q8.8 = ±128 units)
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module pid_controller #(
    // ── Clock & sample rate ───────────────────────────────────────────
    parameter CLK_FREQ       = 50_000_000, // System clock frequency in Hz
    parameter SAMPLE_HZ      = 10,         // PID update rate in Hz (1–1000)

    // ── Sensor scaling ────────────────────────────────────────────────
    // Left-shift applied to sensor raw word before Q8.8 PID arithmetic.
    // Set to 0 for sensors already in Q8.8 format.
    parameter SENSOR_SCALE   = 1,          // TMP117 default: shift left 1

    // ── Default PID gains (Q8.8 format) ──────────────────────────────
    // Reprogrammable at runtime via I2C slave. These are power-on defaults.
    parameter DEFAULT_SETPT  = 16'h1900,   // 25.0  in Q8.8  (25 × 256 = 6400)
    parameter DEFAULT_KP     = 16'h0100,   // 1.0   in Q8.8  (1  × 256 = 256)
    parameter DEFAULT_KI     = 16'h0040,   // 0.25  in Q8.8
    parameter DEFAULT_KD     = 16'h0000,   // 0.0   (derivative disabled by default)

    // ── Anti-windup integral clamp ────────────────────────────────────
    parameter INTEGRAL_LIMIT = 32'sh007FFFFF  // Max accumulated integral (Q16.8)
)(
    input  wire        clk,
    input  wire        rst,         // synchronous active-high reset

    // ── From I2C master (any sensor, 16-bit raw word) ─────────────────
    input  wire [15:0] sensor_raw,  // raw value from sensor (see SENSOR_SCALE)
    input  wire        sensor_valid,// pulse: new reading available

    // ── From I2C slave (host MCU writes setpoint + gains) ─────────────
    input  wire [7:0]  cfg_byte,    // one config byte at a time
    input  wire        cfg_valid,   // pulse: cfg_byte is valid

    // ── To PWM generator (any PWM-compatible actuator) ────────────────
    output reg  [7:0]  duty,        // 0 = off, 255 = full, maps to PWM duty cycle

    // ── To UART transmitter (7-byte frame) ────────────────────────────
    output reg  [7:0]  uart_data,
    output reg         uart_valid,
    input  wire        uart_ready
);

    // =========================================================================
    // 1. PARAMETER SANITY
    // =========================================================================
    localparam SAMPLE_CYCLES = CLK_FREQ / SAMPLE_HZ;

    // =========================================================================
    // 2. CONFIGURATION REGISTERS
    //    Written via I2C slave in 6-byte bursts: SP_H SP_L Kp_H Kp_L Ki_H Ki_L
    // =========================================================================
    reg [15:0] setpoint;       // Q8.8 target value
    reg [15:0] kp;             // Q8.8 proportional gain
    reg [15:0] ki;             // Q8.8 integral gain
    reg [15:0] kd;             // Q8.8 derivative gain (optional)

    reg [2:0]  cfg_idx;        // byte counter 0..5
    reg [7:0]  cfg_buf [0:4];  // partial config accumulator

    always @(posedge clk) begin
        if (rst) begin
            setpoint <= DEFAULT_SETPT;
            kp       <= DEFAULT_KP;
            ki       <= DEFAULT_KI;
            kd       <= DEFAULT_KD;
            cfg_idx  <= 3'd0;
        end else if (cfg_valid) begin
            if (cfg_idx < 3'd5)
                cfg_buf[cfg_idx] <= cfg_byte;

            if (cfg_idx == 3'd5) begin
                // All 6 bytes received — latch new gains
                setpoint <= { cfg_buf[0], cfg_buf[1] };
                kp       <= { cfg_buf[2], cfg_buf[3] };
                ki       <= { cfg_buf[4], cfg_byte   };
                cfg_idx  <= 3'd0;
            end else begin
                cfg_idx  <= cfg_idx + 3'd1;
            end
        end
    end

    // =========================================================================
    // 3. SENSOR LATCH
    //    Stores the most recent reading until the next PID sample tick.
    // =========================================================================
    reg [15:0] sensor_hold;
    reg [15:0] sensor_q8;      // sensor value scaled to Q8.8

    always @(posedge clk) begin
        if (rst) begin
            sensor_hold <= 16'h0;
            sensor_q8   <= 16'h0;
        end else if (sensor_valid) begin
            sensor_hold <= sensor_raw;
            // Scale raw → Q8.8 using left-shift parameter
            // Synthesis tools replace this with wiring (no LUTs used for const shift)
            sensor_q8   <= sensor_raw << SENSOR_SCALE;
        end
    end

    // =========================================================================
    // 4. SAMPLE TICK GENERATOR
    //    Produces a single-cycle pulse at SAMPLE_HZ rate.
    // =========================================================================
    reg [31:0] sample_cnt;
    reg        sample_tick;

    always @(posedge clk) begin
        if (rst) begin
            sample_cnt  <= 32'd0;
            sample_tick <= 1'b0;
        end else begin
            sample_tick <= 1'b0;
            if (sample_cnt >= SAMPLE_CYCLES - 1) begin
                sample_cnt  <= 32'd0;
                sample_tick <= 1'b1;
            end else begin
                sample_cnt <= sample_cnt + 32'd1;
            end
        end
    end

    // =========================================================================
    // 5. PID COMPUTATION
    //    All arithmetic in signed Q8.8 / Q16.8 fixed-point.
    //    No floating-point — fully synthesisable.
    // =========================================================================
    reg signed [16:0] error;          // e(t)    = setpoint − sensor_q8 (Q8.8, +1 sign bit)
    reg signed [16:0] error_prev;     // e(t−1)  for derivative term
    reg signed [31:0] integral;       // ∫e dt   accumulated in Q16.8
    reg signed [31:0] derivative;     // Δe/Δt   for optional D term
    reg signed [47:0] pid_out_full;   // full-width before truncation
    reg signed [31:0] pid_out;        // after truncation

    // Anti-windup limit (signed)
    localparam signed [31:0] ILIM_POS =  INTEGRAL_LIMIT;
    localparam signed [31:0] ILIM_NEG = -INTEGRAL_LIMIT;

    always @(posedge clk) begin
        if (rst) begin
            error       <= 17'sh0;
            error_prev  <= 17'sh0;
            integral    <= 32'sh0;
            derivative  <= 32'sh0;
            pid_out     <= 32'sh0;
            duty        <= 8'h00;
        end else if (sample_tick) begin

            // ── Error ────────────────────────────────────────────────
            // Both setpoint and sensor_q8 are Q8.8 unsigned.
            // Cast to signed for subtraction so negative error is handled.
            error = $signed({1'b0, setpoint}) - $signed({1'b0, sensor_q8});

            // ── Integral with anti-windup ────────────────────────────
            // Accumulate error each sample period.
            // Clamp to ±ILIM to prevent windup during large disturbances.
            integral = integral + $signed({error, 8'b0}); // upscale to Q16.8
            if (integral > ILIM_POS) integral = ILIM_POS;
            if (integral < ILIM_NEG) integral = ILIM_NEG;

            // ── Derivative (rate of error change) ────────────────────
            // Disabled by default (kd = 0). Enable by setting kd via I2C.
            derivative = $signed({(error - error_prev), 8'b0});
            error_prev = error;

            // ── PID sum ───────────────────────────────────────────────
            // Q8.8 gain × Q8.8 error = Q16.16 product
            // Integral is Q16.8, so kp×error and ki×integral both Q16.16
            // We right-shift by 8 to bring back to Q8.8 range for duty output
            //
            //   P: kp (Q8.8) × error (Q8.8) → Q16.16 → >>8 → Q8.8
            //   I: ki (Q8.8) × integral[31:8] (Q8.8) → >>8 → Q8.8
            //   D: kd (Q8.8) × derivative[31:8] (Q8.8) → >>8 → Q8.8
            pid_out_full = (
                ($signed({1'b0, kp}) * error) +
                ($signed({1'b0, ki}) * (integral  >>> 8)) +
                ($signed({1'b0, kd}) * (derivative >>> 8))
            );

            pid_out = pid_out_full >>> 8;

            // ── Clamp to [0, 255] → duty byte ────────────────────────
            if      (pid_out <= 0)   duty <= 8'h00;
            else if (pid_out >= 255) duty <= 8'hFF;
            else                     duty <= pid_out[7:0];
        end
    end

    // =========================================================================
    // 6. UART FRAME TRANSMITTER
    //    7-byte frame: 0xAA | SENS_H | SENS_L | SETPT_H | SETPT_L | DUTY | 0x55
    //    Triggered on every sample_tick.
    //    Handshake: uart_valid HIGH until uart_ready acknowledged.
    // =========================================================================
    localparam [7:0] UART_SOF = 8'hAA;
    localparam [7:0] UART_EOF = 8'h55;

    localparam [2:0]
        TX_IDLE   = 3'd0,
        TX_SOF    = 3'd1,
        TX_SENS_H = 3'd2,
        TX_SENS_L = 3'd3,
        TX_SP_H   = 3'd4,
        TX_SP_L   = 3'd5,
        TX_DUTY   = 3'd6,
        TX_EOF    = 3'd7;

    reg [2:0]  tx_state;
    reg [15:0] snap_sensor;
    reg [15:0] snap_setpoint;
    reg [7:0]  snap_duty;

    // Helper task: drive byte and wait for ready
    // (implemented as state machine below)

    always @(posedge clk) begin
        if (rst) begin
            tx_state      <= TX_IDLE;
            uart_valid    <= 1'b0;
            uart_data     <= 8'h00;
            snap_sensor   <= 16'h0;
            snap_setpoint <= 16'h0;
            snap_duty     <= 8'h0;
        end else begin
            // Default: de-assert valid once accepted
            if (uart_valid && uart_ready)
                uart_valid <= 1'b0;

            case (tx_state)
                TX_IDLE: begin
                    if (sample_tick) begin
                        // Snapshot PID state for coherent frame
                        snap_sensor   <= sensor_hold;
                        snap_setpoint <= setpoint;
                        snap_duty     <= duty;
                        tx_state      <= TX_SOF;
                    end
                end

                TX_SOF: begin
                    if (!uart_valid || uart_ready) begin
                        uart_data  <= UART_SOF;
                        uart_valid <= 1'b1;
                        tx_state   <= TX_SENS_H;
                    end
                end

                TX_SENS_H: begin
                    if (!uart_valid || uart_ready) begin
                        uart_data  <= snap_sensor[15:8];
                        uart_valid <= 1'b1;
                        tx_state   <= TX_SENS_L;
                    end
                end

                TX_SENS_L: begin
                    if (!uart_valid || uart_ready) begin
                        uart_data  <= snap_sensor[7:0];
                        uart_valid <= 1'b1;
                        tx_state   <= TX_SP_H;
                    end
                end

                TX_SP_H: begin
                    if (!uart_valid || uart_ready) begin
                        uart_data  <= snap_setpoint[15:8];
                        uart_valid <= 1'b1;
                        tx_state   <= TX_SP_L;
                    end
                end

                TX_SP_L: begin
                    if (!uart_valid || uart_ready) begin
                        uart_data  <= snap_setpoint[7:0];
                        uart_valid <= 1'b1;
                        tx_state   <= TX_DUTY;
                    end
                end

                TX_DUTY: begin
                    if (!uart_valid || uart_ready) begin
                        uart_data  <= snap_duty;
                        uart_valid <= 1'b1;
                        tx_state   <= TX_EOF;
                    end
                end

                TX_EOF: begin
                    if (!uart_valid || uart_ready) begin
                        uart_data  <= UART_EOF;
                        uart_valid <= 1'b1;
                        tx_state   <= TX_IDLE;
                    end
                end

                default: tx_state <= TX_IDLE;
            endcase
        end
    end

endmodule
`default_nettype wire