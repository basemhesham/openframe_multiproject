// =============================================================================
// pwm_gen.v
// Generic 8-bit PWM Generator
// =============================================================================
// Compatible with any PWM-driven actuator:
//   - DC brushless fan (gate via N-channel MOSFET, e.g. IRLZ44N)
//   - Servo motor     (needs additional period stretcher for 50 Hz servo signal)
//   - Resistive heater (solid-state relay or MOSFET)
//   - LED dimmer       (direct output or via gate driver)
//   - Stepper/DC motor driver (e.g. DRV8833 PWM input)
//
// PWM frequency = CLK_FREQ / (2^RESOLUTION)
//   8-bit at 50 MHz → 50,000,000 / 256 ≈ 195,312 Hz  (above audible, ideal for fans)
//   8-bit at 25 MHz → 25,000,000 / 256 ≈  97,656 Hz
//
// Duty cycle:
//   duty = 0   → pwm_out always LOW  (0%,   actuator fully off)
//   duty = 128 → pwm_out 50% HIGH    (50%,  actuator half power)
//   duty = 255 → pwm_out always HIGH (100%, actuator full power)
//
// Output polarity:
//   ACTIVE_HIGH = 1 (default): pwm_out HIGH = actuator driven
//   ACTIVE_HIGH = 0           : pwm_out LOW  = actuator driven (inverted)
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module pwm_gen #(
    parameter CLK_FREQ   = 50_000_000, // system clock in Hz
    parameter RESOLUTION = 8,          // PWM bit depth (8 = 256 levels)
    parameter ACTIVE_HIGH = 1          // 1 = normal, 0 = inverted output
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire [RESOLUTION-1:0]   duty,       // from PID controller
    output reg                     pwm_out     // to MOSFET gate or actuator input
);

    reg [RESOLUTION-1:0] counter;

    always @(posedge clk) begin
        if (rst) begin
            counter <= {RESOLUTION{1'b0}};
            pwm_out <= ACTIVE_HIGH ? 1'b0 : 1'b1;
        end else begin
            // Free-running counter wraps automatically at 2^RESOLUTION
            counter <= counter + 1'b1;

            // Compare: output is HIGH while counter < duty
            if (ACTIVE_HIGH)
                pwm_out <= (counter < duty) ? 1'b1 : 1'b0;
            else
                pwm_out <= (counter < duty) ? 1'b0 : 1'b1;
        end
    end

endmodule
`default_nettype wire