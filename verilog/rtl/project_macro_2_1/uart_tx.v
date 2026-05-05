// uart_tx.v
// 8N1 UART transmitter — no external dependencies
// Parameterised baud rate. Works with any LibreLane/OpenLane PDK.
`default_nettype none
`timescale 1ns/1ps
module uart_tx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data,
    input  wire       valid,
    output reg        ready,
    output reg        tx
);
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    localparam S_IDLE  = 2'd0,
               S_START = 2'd1,
               S_DATA  = 2'd2,
               S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [12:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shift_reg;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE; tx <= 1; ready <= 1;
            clk_cnt <= 0; bit_idx <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    tx <= 1; ready <= 1;
                    if (valid) begin
                        shift_reg <= data;
                        ready <= 0;
                        clk_cnt <= 0;
                        state <= S_START;
                    end
                end
                S_START: begin
                    tx <= 0;
                    if (clk_cnt < CLKS_PER_BIT - 1) clk_cnt <= clk_cnt + 1;
                    else begin clk_cnt <= 0; bit_idx <= 0; state <= S_DATA; end
                end
                S_DATA: begin
                    tx <= shift_reg[bit_idx];
                    if (clk_cnt < CLKS_PER_BIT - 1) clk_cnt <= clk_cnt + 1;
                    else begin
                        clk_cnt <= 0;
                        if (bit_idx == 7) state <= S_STOP;
                        else bit_idx <= bit_idx + 1;
                    end
                end
                S_STOP: begin
                    tx <= 1;
                    if (clk_cnt < CLKS_PER_BIT - 1) clk_cnt <= clk_cnt + 1;
                    else begin clk_cnt <= 0; ready <= 1; state <= S_IDLE; end
                end
            endcase
        end
    end
endmodule