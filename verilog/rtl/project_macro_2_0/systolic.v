`timescale 1ns/1ps
`default_nettype none

module systolic #(
    parameter SYSTOLIC_ARRAY_WIDTH = 4
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [63:0] sys_data_in,
    input  wire [63:0] sys_weight_in,
    input  wire [3:0]  sys_accept_w,
    input  wire        sys_start,
    input  wire        sys_switch_in,
    input  wire [15:0] ub_rd_col_size_in,
    input  wire        ub_rd_col_size_valid_in,
    output wire [63:0] sys_data_out,
    output wire [3:0]  sys_valid_out
);

    // Skew the start signal for each row to match the input data wavefront
    reg [SYSTOLIC_ARRAY_WIDTH-1:0] sys_start_skewed;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sys_start_skewed <= {SYSTOLIC_ARRAY_WIDTH{1'b0}};
        end else begin
            sys_start_skewed[0] <= sys_start;
            sys_start_skewed[SYSTOLIC_ARRAY_WIDTH-1:1] <= sys_start_skewed[SYSTOLIC_ARRAY_WIDTH-2:0];
        end
    end

    genvar i, j;
    generate
        for (i = 0; i < SYSTOLIC_ARRAY_WIDTH; i = i + 1) begin : rows
            for (j = 0; j < SYSTOLIC_ARRAY_WIDTH; j = j + 1) begin : cols
                wire [15:0] pe_psum_in;
                wire [15:0] pe_psum_out;
                wire        pe_valid_in;
                wire        pe_valid_out;
                wire [15:0] pe_activation_in;
                wire [15:0] pe_activation_out;
                wire [15:0] pe_weight_in;
                wire [15:0] pe_weight_out;

                if (j == 0) begin
                    assign pe_activation_in = {{8{sys_data_in[i*16+7]}}, sys_data_in[i*16 +: 8]};
                    assign pe_valid_in = sys_start_skewed[i];
                end else begin
                    assign pe_activation_in = cols[j-1].pe_activation_out;
                    assign pe_valid_in = cols[j-1].pe_valid_out;
                end

                if (i == 0) begin
                    assign pe_psum_in = 16'b0;
                    assign pe_weight_in = {{8{sys_weight_in[j*16+7]}}, sys_weight_in[j*16 +: 8]};
                end else begin
                    assign pe_psum_in = rows[i-1].cols[j].pe_psum_out;
                    assign pe_weight_in = rows[i-1].cols[j].pe_weight_out;
                end

                pe #(
                    .WII_A(8), .WIF_A(8),
                    .WII_W(8), .WIF_W(8),
                    .WOI(16), .WOF(8)
                ) u_pe (
                    .clk(clk),
                    .rst(rst),
                    .psum_in(pe_psum_in),
                    .weight_in(pe_weight_in),
                    .accept_w_in(sys_accept_w[j]),
                    .activation_in(pe_activation_in),
                    .valid_in(pe_valid_in),
                    .switch_in(sys_switch_in),
                    .enabled(1'b1),
                    .psum_out(pe_psum_out),
                    .weight_out(pe_weight_out),
                    .activation_out(pe_activation_out),
                    .valid_out(pe_valid_out),
                    .switch_out(),
                    .overflow_out()
                );

                if (i == SYSTOLIC_ARRAY_WIDTH - 1) begin
                    assign sys_data_out[j*16 +: 16] = pe_psum_out;
                    assign sys_valid_out[j] = pe_valid_out;
                end
            end
        end
    endgenerate

endmodule
