`timescale 1ns/1ps
`default_nettype none

module systolic_wrapper (
    input wire clk,
    input wire rst_n,

    // External Interface for Data Memory
    input  wire [7:0]  ext_data_we,
    input  wire [7:0]  ext_data_addr,
    input  wire [63:0] ext_data_di,
    output wire [63:0] ext_data_do,

    // External Interface for Weight Memory
    input  wire [7:0]  ext_weight_we,
    input  wire [7:0]  ext_weight_addr,
    input  wire [63:0] ext_weight_di,
    output wire [63:0] ext_weight_do,

    // External Interface for Output Memory
    input  wire [7:0]  ext_output_addr,
    output wire [63:0] ext_output_do,

    // Control and Status
    input  wire        start,
    input  wire [15:0] data_len,
    input  wire [3:0]  col_mask,
    output reg         busy,
    output reg         done
);

    wire rst = ~rst_n;

    // --------------------------------------------------
    // State Machine
    // --------------------------------------------------
    localparam IDLE           = 3'd0;
    localparam LOAD_WEIGHTS   = 3'd1;
    localparam SWITCH_WEIGHTS = 3'd2;
    localparam PROCESS_DATA   = 3'd3;
    localparam WAIT_OUTPUT    = 3'd4;
    localparam DONE           = 3'd5;

    reg [2:0] state;
    reg [15:0] counter;
    reg [15:0] output_counter;

    // --------------------------------------------------
    // Memory Signals
    // --------------------------------------------------
    wire [7:0]  data_mem_we;
    wire [4:0]  data_mem_addr;
    wire [63:0] data_mem_di;
    wire [63:0] data_mem_do;

    wire [7:0]  weight_mem_we;
    wire [4:0]  weight_mem_addr;
    wire [63:0] weight_mem_di;
    wire [63:0] weight_mem_do;

    wire [7:0]  output_mem_we;
    wire [4:0]  output_mem_addr;
    wire [63:0] output_mem_di;
    wire [63:0] output_mem_do;

    // --------------------------------------------------
    // Systolic Array Signals
    // --------------------------------------------------
    reg [63:0] sys_data_in;
    reg [63:0] sys_weight_in;
    reg [3:0]  sys_accept_w;
    reg        sys_start;
    reg        sys_switch_in;
    wire [63:0] sys_data_out;
    wire [3:0]  sys_valid_out;

    // --------------------------------------------------
    // Skewing/Deskewing Logic
    // --------------------------------------------------
    reg [15:0] data_skew_r1_0;
    reg [15:0] data_skew_r2_0, data_skew_r2_1;
    reg [15:0] data_skew_r3_0, data_skew_r3_1, data_skew_r3_2;

    reg [15:0] res_deskew_c0_0, res_deskew_c0_1, res_deskew_c0_2;
    reg [15:0] res_deskew_c1_0, res_deskew_c1_1;
    reg [15:0] res_deskew_c2_0;

    reg [3:0]  valid_deskew_0, valid_deskew_1, valid_deskew_2, valid_deskew_3;

    wire [63:0] skewed_data_in;
    assign skewed_data_in[15:0]  = sys_data_in[15:0];
    assign skewed_data_in[31:16] = data_skew_r1_0;
    assign skewed_data_in[47:32] = data_skew_r2_1;
    assign skewed_data_in[63:48] = data_skew_r3_2;

    wire [63:0] deskewed_data_out;
    assign deskewed_data_out[15:0]  = res_deskew_c0_2;
    assign deskewed_data_out[31:16] = res_deskew_c1_1;
    assign deskewed_data_out[47:32] = res_deskew_c2_0;
    assign deskewed_data_out[63:48] = sys_data_out[63:48];

    wire deskewed_valid = sys_valid_out[3];

    // --------------------------------------------------
    // MUX Memory Ports
    // --------------------------------------------------
    assign data_mem_we   = busy ? 8'b0 : ext_data_we;
    assign data_mem_addr = busy ? counter[4:0] : ext_data_addr[4:0];
    assign data_mem_di   = busy ? 64'b0 : ext_data_di;
    assign ext_data_do   = data_mem_do;

    assign weight_mem_we   = busy ? 8'b0 : ext_weight_we;
    assign weight_mem_addr = busy ? counter[4:0] : ext_weight_addr[4:0];
    assign weight_mem_di   = busy ? 64'b0 : ext_weight_di;
    assign ext_weight_do   = weight_mem_do;

    assign output_mem_we   = (busy && deskewed_valid) ? 8'hFF : 8'b0;
    assign output_mem_addr = (busy) ? output_counter[4:0] : ext_output_addr[4:0];
    assign output_mem_di   = deskewed_data_out;
    assign ext_output_do   = output_mem_do;

    // --------------------------------------------------
    // Control and Skewing Logic
    // --------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            counter <= 16'b0;
            output_counter <= 16'b0;
            sys_data_in <= 64'b0;
            sys_weight_in <= 64'b0;
            sys_accept_w <= 4'b0;
            sys_start <= 1'b0;
            sys_switch_in <= 1'b0;
            data_skew_r1_0 <= 16'b0;
            data_skew_r2_0 <= 16'b0;
            data_skew_r2_1 <= 16'b0;
            data_skew_r3_0 <= 16'b0;
            data_skew_r3_1 <= 16'b0;
            data_skew_r3_2 <= 16'b0;
            res_deskew_c0_0 <= 16'b0;
            res_deskew_c0_1 <= 16'b0;
            res_deskew_c0_2 <= 16'b0;
            res_deskew_c1_0 <= 16'b0;
            res_deskew_c1_1 <= 16'b0;
            res_deskew_c2_0 <= 16'b0;
            valid_deskew_0 <= 4'b0;
            valid_deskew_1 <= 4'b0;
            valid_deskew_2 <= 4'b0;
            valid_deskew_3 <= 4'b0;
        end else begin
            // Deskewing logic - always active when busy
            if (busy) begin
                res_deskew_c0_0 <= sys_data_out[15:0];
                res_deskew_c0_1 <= res_deskew_c0_0;
                res_deskew_c0_2 <= res_deskew_c0_1;
                res_deskew_c1_0 <= sys_data_out[31:16];
                res_deskew_c1_1 <= res_deskew_c1_0;
                res_deskew_c2_0 <= sys_data_out[47:32];
                valid_deskew_0 <= sys_valid_out;
                valid_deskew_1 <= valid_deskew_0;
                valid_deskew_2 <= valid_deskew_1;
                valid_deskew_3 <= valid_deskew_2;
            end

            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        state <= LOAD_WEIGHTS;
                        busy <= 1'b1;
                        counter <= 16'b0;
                        output_counter <= 16'b0;
                    end
                end

                LOAD_WEIGHTS: begin
                    if (counter >= 1 && counter <= 4) begin
                        sys_weight_in <= weight_mem_do;
                        sys_accept_w <= col_mask;
                    end else begin
                        sys_accept_w <= 4'b0;
                    end

                    if (counter == 5) begin
                        state <= SWITCH_WEIGHTS;
                        counter <= 16'b0;
                    end else begin
                        counter <= counter + 1;
                    end
                end

                SWITCH_WEIGHTS: begin
                    sys_switch_in <= 1'b1;
                    state <= PROCESS_DATA;
                    counter <= 16'b0;
                end

                PROCESS_DATA: begin
                    sys_switch_in <= 1'b0;
                    
                    if (counter < data_len) begin
                        sys_start <= 1'b1;
                    end else begin
                        sys_start <= 1'b0;
                    end

                    sys_data_in <= data_mem_do;

                    // Input Skewing
                    data_skew_r1_0 <= sys_data_in[31:16];
                    data_skew_r2_0 <= sys_data_in[47:32];
                    data_skew_r2_1 <= data_skew_r2_0;
                    data_skew_r3_0 <= sys_data_in[63:48];
                    data_skew_r3_1 <= data_skew_r3_0;
                    data_skew_r3_2 <= data_skew_r3_1;

                    if (counter == data_len + 5) begin
                        state <= WAIT_OUTPUT;
                        counter <= 16'b0;
                    end else begin
                        counter <= counter + 1;
                    end
                end

                WAIT_OUTPUT: begin
                    // Flush Input Skewing
                    data_skew_r1_0 <= sys_data_in[31:16];
                    data_skew_r2_0 <= sys_data_in[47:32];
                    data_skew_r2_1 <= data_skew_r2_0;
                    data_skew_r3_0 <= sys_data_in[63:48];
                    data_skew_r3_1 <= data_skew_r3_0;
                    data_skew_r3_2 <= data_skew_r3_1;

                    sys_start <= 1'b0;
                    sys_data_in <= 64'b0;
                    if (counter == 20) begin
                        state <= DONE;
                    end else begin
                        counter <= counter + 1;
                    end
                end

                DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= IDLE;
                end
            endcase

            if (busy && deskewed_valid) begin
                output_counter <= output_counter + 1;
            end
        end
    end

    // --------------------------------------------------
    // Memory Instances
    // --------------------------------------------------
    DFFRAM #(
        .WORDS(32),
        .WSIZE(8)
    ) data_mem (
        .CLK(clk), .EN0(1'b1), .WE0(data_mem_we), .A0(data_mem_addr), .Di0(data_mem_di), .Do0(data_mem_do)
    );

    DFFRAM #(
        .WORDS(32),
        .WSIZE(8)
    ) weight_mem (
        .CLK(clk), .EN0(1'b1), .WE0(weight_mem_we), .A0(weight_mem_addr), .Di0(weight_mem_di), .Do0(weight_mem_do)
    );

    DFFRAM #(
        .WORDS(32),
        .WSIZE(8)
    ) output_mem (
        .CLK(clk), .EN0(1'b1), .WE0(output_mem_we), .A0(output_mem_addr), .Di0(output_mem_di), .Do0(output_mem_do)
    );

    // --------------------------------------------------
    // Systolic Array Instance
    // --------------------------------------------------
    systolic #(
        .SYSTOLIC_ARRAY_WIDTH(4)
    ) u_systolic (
        .clk(clk),
        .rst(rst),
        .sys_data_in(skewed_data_in),
        .sys_weight_in(sys_weight_in),
        .sys_accept_w(sys_accept_w),
        .sys_start(sys_start),
        .sys_switch_in(sys_switch_in),
        .ub_rd_col_size_in(16'd4),
        .ub_rd_col_size_valid_in(1'b1),
        .sys_data_out(sys_data_out),
        .sys_valid_out(sys_valid_out)
    );

endmodule
