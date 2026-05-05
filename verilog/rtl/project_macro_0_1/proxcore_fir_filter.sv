module proxcore_fir_filter (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire  [15:0]                 sample_in,
    input  wire                         sample_valid,

    // Runtime-programmable coefficients (symmetric — only 8 needed)
    input  wire signed [15:0]           coeff_in0,
    input  wire signed [15:0]           coeff_in1,
    input  wire signed [15:0]           coeff_in2,
    input  wire signed [15:0]           coeff_in3,
    input  wire signed [15:0]           coeff_in4,
    input  wire signed [15:0]           coeff_in5,
    input  wire signed [15:0]           coeff_in6,
    input  wire signed [15:0]           coeff_in7,

    output reg   [15:0]                 result_out,
    output reg                          result_valid
);

    // Parameters
    localparam TAPS            = 16;
    localparam ORDER           = 15;
    localparam COEFF_WIDTH     = 16;
    localparam COEFF_FRAC_BITS = 15;
    localparam DATA_WIDTH      = 16;
    localparam ACC_WIDTH       = 36;
    localparam LATENCY         = 5;

    // Latency calculation
    localparam BASE_LATENCY = 2;
    localparam PIPE_DEPTH   = LATENCY - BASE_LATENCY;

    // Symmetric structure parameters
    localparam CENTER_TAP = TAPS / 2;

    // Module scope declarations
    logic  [DATA_WIDTH-1:0] data_reg [0:TAPS-1];
    logic signed [ACC_WIDTH-1:0]  accum;
    logic signed [ACC_WIDTH-1:0]  scaled_acc;
    logic  [DATA_WIDTH-1:0] result_temp;

    // Symmetric structure signals
    logic [DATA_WIDTH:0]              sum_pre_u [0:CENTER_TAP-1];
    logic signed [DATA_WIDTH+1:0]     sum_pre_s [0:CENTER_TAP-1];
    logic signed [ACC_WIDTH-1:0]        mult    [0:CENTER_TAP-1];

    // Pipeline registers
    logic signed [ACC_WIDTH-1:0]  pipe_reg [0:PIPE_DEPTH-1];

    // Valid pipeline
    logic valid_pipe [0:LATENCY-2];

    // Wire coefficient inputs into indexable array
    wire signed [COEFF_WIDTH-1:0] coeffs [0:CENTER_TAP-1];
    assign coeffs[0] = coeff_in0;
    assign coeffs[1] = coeff_in1;
    assign coeffs[2] = coeff_in2;
    assign coeffs[3] = coeff_in3;
    assign coeffs[4] = coeff_in4;
    assign coeffs[5] = coeff_in5;
    assign coeffs[6] = coeff_in6;
    assign coeffs[7] = coeff_in7;

    // Loop iterators
    integer k;

    // Input shift register
    always_ff @(posedge clk or negedge rst_n) begin
    integer i_shift;
        if (!rst_n) begin
            for (i_shift = 0; i_shift < TAPS; i_shift = i_shift + 1) begin
                data_reg[i_shift] <= '0;
            end
        end else if (sample_valid) begin
            data_reg[0] <= sample_in;
            for (i_shift = 1; i_shift < TAPS; i_shift = i_shift + 1) begin
                data_reg[i_shift] <= data_reg[i_shift-1];
            end
        end
    end

    // Symmetric FIR computation (combinational)
    always_comb begin
        // Pre-add symmetric pairs (unsigned)
        for (k = 0; k < CENTER_TAP; k = k + 1) begin
            sum_pre_u[k] = data_reg[k] + data_reg[TAPS-1-k];
        end

        // Zero-extend to signed
        for (k = 0; k < CENTER_TAP; k = k + 1) begin
            sum_pre_s[k] = {1'b0, sum_pre_u[k]};
        end

        // Multiplications (signed x signed)
        for (k = 0; k < CENTER_TAP; k = k + 1) begin
            mult[k] = sum_pre_s[k] * coeffs[k];
        end

        // Accumulation
        accum = '0;
        for (k = 0; k < CENTER_TAP; k = k + 1) begin
            accum = accum + mult[k];
        end
    end

    // Pipeline stages
    generate
        if (PIPE_DEPTH > 0) begin : gen_pipe
            always_ff @(posedge clk or negedge rst_n) begin
            integer i_pipe;
                if (!rst_n) begin
                    for (i_pipe = 0; i_pipe < PIPE_DEPTH; i_pipe = i_pipe + 1) begin
                        pipe_reg[i_pipe] <= '0;
                    end
                end else begin
                    pipe_reg[0] <= accum;
                    for (i_pipe = 1; i_pipe < PIPE_DEPTH; i_pipe = i_pipe + 1) begin
                        pipe_reg[i_pipe] <= pipe_reg[i_pipe-1];
                    end
                end
            end

            assign scaled_acc  = pipe_reg[PIPE_DEPTH-1] >>> COEFF_FRAC_BITS;
            assign result_temp = scaled_acc[DATA_WIDTH-1:0];

        end else begin : gen_no_pipe
            assign scaled_acc  = accum >>> COEFF_FRAC_BITS;
            assign result_temp = scaled_acc[DATA_WIDTH-1:0];
        end
    endgenerate

    // Output register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_out <= '0;
        end else begin
            result_out <= result_temp;
        end
    end

    // Valid signal pipeline
    always_ff @(posedge clk or negedge rst_n) begin
    integer i_valid;
        if (!rst_n) begin
            for (i_valid = 0; i_valid < LATENCY-1; i_valid = i_valid + 1) begin
                valid_pipe[i_valid] <= 1'b0;
            end
        end else begin
            valid_pipe[0] <= sample_valid;
            for (i_valid = 1; i_valid < LATENCY-1; i_valid = i_valid + 1) begin
                valid_pipe[i_valid] <= valid_pipe[i_valid-1];
            end
        end
    end

    // Result valid register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_valid <= 1'b0;
        end else begin
            result_valid <= valid_pipe[LATENCY-2];
        end
    end

endmodule