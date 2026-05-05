//================================================
// PE.v - Processing Element for Weight-Stationary Systolic Array
// NeuralTram: 8-bit INT8 Weights × INT8 Activations → INT16 Partial Sums
//
// Standard: IEEE 1364-2001 Verilog
// Licensed for ASIC: SkyWater 130nm (sky130)
//================================================

`timescale 1ns/1ps
`default_nettype none

module pe #(
    parameter WII_A = 8,      // Input integer bits (activation)
    parameter WIF_A = 8,      // Input fractional bits (activation)
    parameter WII_W = 8,      // Input integer bits (weight)
    parameter WIF_W = 8,      // Input fractional bits (weight)
    parameter WOI   = 16,     // Output integer bits (partial sum)
    parameter WOF   = 8       // Output fractional bits (partial sum)
)(
    input wire clk,
    input wire rst,

    // North wires (vertical psum flow)
    input wire signed [15:0] psum_in,        // Partial sum from above
    input wire signed [15:0] weight_in,      // Weight from above (pre-fetched)
    input wire               accept_w_in,    // Accept (load) weight into shadow buffer

    // West wires (horizontal activation flow)
    input wire signed [15:0] activation_in,  // Input activation (INT8 signed)
    input wire               valid_in,       // Data valid signal
    input wire               switch_in,      // Switch: move weight from shadow → active
    input wire               enabled,        // Column enable (gates computation)

    // South wires (vertical output)
    // FIX: changed from output wire to output reg — driven in always block
    output reg signed [15:0] psum_out,       // Output partial sum
    output reg signed [15:0] weight_out,     // Weight passthrough (to next row)

    // East wires (horizontal output)
    // FIX: changed from output wire to output reg — driven in always block
    output reg signed [15:0] activation_out, // Activation passthrough (to next col)
    output reg               valid_out,      // Valid signal passthrough
    output reg               switch_out,     // Switch signal passthrough
    output wire              overflow_out    // Sticky overflow flag (combinational assign OK)
);

    // ==================== Internal Signals ====================
    wire signed [15:0] mult_out;             // Multiplier output
    wire signed [15:0] mac_out;              // MAC result (mult + accum)

    reg signed [15:0] weight_active;         // Active weight register (foreground buffer)
    reg signed [15:0] weight_shadow;         // Shadow weight register (background buffer)

    wire mult_overflow;                      // Multiplier overflow
    wire add_overflow;                       // Adder overflow

    reg overflow_reg;                        // Sticky overflow tracker

    // ==================== Combinational Logic ====================

    // Fixed-point 16-bit signed multiplication (INT8 × INT8 → INT16)
    assign mult_out = (activation_in * weight_active);

    // Fixed-point 16-bit signed addition (INT16 + INT16 → INT16)
    assign mac_out = (mult_out + psum_in);

    // Simple overflow detection (sign overflow trap)
    assign mult_overflow = ((activation_in[15] == weight_active[15]) &&
                            (mult_out[15] != activation_in[15]));

    assign add_overflow  = ((mult_out[15] == psum_in[15]) &&
                            (mac_out[15]  != mult_out[15]));

    // ==================== Sequential Logic ====================

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            activation_out <= 16'b0;
            weight_active  <= 16'b0;
            weight_shadow  <= 16'b0;
            valid_out      <= 1'b0;
            weight_out     <= 16'b0;
            switch_out     <= 1'b0;
            psum_out       <= 16'b0;
            overflow_reg   <= 1'b0;
        end else if (!enabled) begin
            // When disabled, reset all outputs to zero
            activation_out <= 16'b0;
            weight_active  <= 16'b0;
            weight_shadow  <= 16'b0;
            valid_out      <= 1'b0;
            weight_out     <= 16'b0;
            switch_out     <= 1'b0;
            psum_out       <= 16'b0;
            overflow_reg   <= 1'b0;
        end else begin
            // Pass through control signals
            valid_out  <= valid_in;
            switch_out <= switch_in;

            // Weight switching: shadow → active on switch pulse
            if (switch_in) begin
                weight_active <= weight_shadow;
            end

            // Weight loading: new weight into shadow buffer
            if (accept_w_in) begin
                weight_shadow <= weight_in;
                weight_out    <= weight_in;  // Passthrough to next row
            end else begin
                weight_out <= 16'b0;
            end

            // Data path: process activation and psum only when valid
            if (valid_in) begin
                activation_out <= activation_in;
                psum_out       <= mac_out;
                overflow_reg   <= overflow_reg | mult_overflow | add_overflow;
            end else begin
                activation_out <= 16'b0;
                psum_out       <= 16'b0;
            end
        end
    end

    // overflow_out is a wire driven combinationally — this is fine
    assign overflow_out = overflow_reg;

endmodule
