// ============================================================
// Project      : AegisDSP - Mixed Signal Security ASIC
// Module       : access_control_top
// Date         : April 2026 — rev6: IR path now accepts a
//                1-bit digital sensor input (replaces signed
//                12-bit sample input).
//
// Architecture:
//   ir_in      ──► ir_dsp_core (IR_path.v) ──► motion_detected ──┐
//                                                                 ├──► alarm
//   I2C mic    ──► sound_detector.v         ──► sound_flag      ──┘
//
// FSM: IDLE ──(motion OR sound)──► ALARM ──(5s timeout)──► IDLE
// ============================================================

module access_control_top #(
    parameter CLK_FREQ_HZ  = 50_000_000,
    parameter I2C_FREQ_HZ  = 100_000,
    parameter MIC_ADDR     = 7'h4A,
    parameter MIC_REG      = 8'h00,
    parameter POLL_RATE_HZ = 8_000
) (
    input  wire        clk,
    input  wire        rst_n,

    // IR digital sensor input (1-bit: active high/low)
    input  wire        ir_in,           // 1-bit digital IR sensor
    input  wire        ir_sample_valid, // one-cycle strobe per new sample

    // I2C microphone
    output wire        mic_scl,
    input  wire        mic_scl_in,
    output wire        mic_sda,
    input  wire        mic_sda_in,

    // Outputs
    output wire        motion_active,   // motion_detected is high
    output wire        sound_active,    // sound_flag is high
    output wire        i2c_error_out,   // I2C fault
    output wire        alarm,           // fires on motion OR sound
    output wire        fsm_state_out    // 0=IDLE 1=ALARM (debug)
);

// ============================================================
// SECTION 1 — IR signal path
// ============================================================
wire motion_detected;

ir_dsp_core u_ir (
    .clk             (clk),
    .rst_n           (rst_n),
    .ir_in           (ir_in),           // 1-bit digital IR sensor
    .sample_valid    (ir_sample_valid),
    .motion_detected (motion_detected)
);

// ============================================================
// SECTION 2 — I2C audio path
// ============================================================
wire sound_flag;
wire i2c_err;

sound_detector #(
    .CLK_FREQ_HZ  (CLK_FREQ_HZ),
    .I2C_FREQ_HZ  (I2C_FREQ_HZ),
    .SENSOR_ADDR  (MIC_ADDR),
    .SENSOR_REG   (MIC_REG),
    .POLL_RATE_HZ (POLL_RATE_HZ)
) u_audio (
    .clk        (clk),
    .rst_n      (rst_n),
    .scl_out    (mic_scl),
    .scl_in     (mic_scl_in),
    .sda_out    (mic_sda),
    .sda_in     (mic_sda_in),
    .sound_flag (sound_flag),
    .i2c_error  (i2c_err)
);

// ============================================================
// SECTION 3 — 2-state alarm FSM
//
//   IDLE ──(motion_detected || sound_flag)──► ALARM
//   ALARM ──(5 s timeout)──► IDLE
//
// Alarm output is asserted combinatorially as well so it
// fires instantly on sensor trigger even before the FSM
// has clocked into ALARM state.
// ============================================================
localparam IDLE     = 1'b0;
localparam ALARM_ST = 1'b1;

localparam ALARM_HOLD = 28'd250_000_000;  // 5 s at 50 MHz

reg        state;
reg [27:0] timer;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        timer <= 28'd0;
    end else begin
        case (state)

            IDLE: begin
                if (motion_detected || sound_flag) begin
                    state <= ALARM_ST;
                    timer <= 28'd0;
                end
            end

            ALARM_ST: begin
                if (timer >= ALARM_HOLD) begin
                    state <= IDLE;
                    timer <= 28'd0;
                end else
                    timer <= timer + 1;
            end

            default: state <= IDLE;

        endcase
    end
end

// ============================================================
// SECTION 4 — Output assignments
// ============================================================
assign motion_active = motion_detected;
assign sound_active  = sound_flag;
assign i2c_error_out = i2c_err;
assign alarm         = motion_detected || sound_flag || (state == ALARM_ST);
assign fsm_state_out = state;

endmodule
