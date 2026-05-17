module ir_dsp_core (
    input  wire clk,
    input  wire rst_n,

    input  wire ir_in,          // digital IR sensor (0/1)
    input  wire sample_valid,

    output reg  motion_detected
);

// Convert digital input to signed signal (+1 / -1)
wire signed [15:0] x_ext = ir_in ? 16'sd32767 : -16'sd32768;

// Delay registers
reg signed [15:0] x_d1;
reg signed [15:0] y_d1;

// alpha = 0.95 in Q1.15
localparam signed [15:0] ALPHA = 16'sd31130;

// High-pass filter
wire signed [31:0] mul = ALPHA * y_d1;

wire signed [15:0] hpf_out =
    x_ext - x_d1 + mul[30:15];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        x_d1 <= 0;
        y_d1 <= 0;
    end else if (sample_valid) begin
        x_d1 <= x_ext;
        y_d1 <= hpf_out;
    end
end

// Absolute value
wire signed [15:0] abs_val =
    hpf_out[15] ? -hpf_out : hpf_out;

// Energy accumulator
reg [23:0] energy;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        energy <= 0;
    else if (sample_valid)
        energy <= energy - (energy >> 6) + abs_val;
end

// Thresholds (may need tuning for digital input)
localparam [23:0] TH_ON  = 24'd20000;
localparam [23:0] TH_OFF = 24'd10000;

// Motion detection
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        motion_detected <= 0;
    else if (energy > TH_ON)
        motion_detected <= 1;
    else if (energy < TH_OFF)
        motion_detected <= 0;
end

endmodule
