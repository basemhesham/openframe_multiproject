`timescale 1ns/1ps

//==============================================================================
// Copyright (c) 2025-2026 nativechips.ai
// Author: Mohamed Shalan <shalan@nativechips.ai>
// SPDX-License-Identifier: Apache-2.0
//==============================================================================

`default_nettype none

//------------------------------------------------------------------------------
// nc_sercom_usart_tx: USART Transmitter
// Supports configurable data bits (5-9), parity, stop bits
//------------------------------------------------------------------------------
module nc_sercom_usart_tx #(
    parameter FIFO_DEPTH = 4,
    parameter DATA_WIDTH = 32
)(
    input  wire        clk,
    input  wire        rst_n,

    // Control
    input  wire        enable,
    input  wire        tx_en,
    input  wire [15:0] clkdiv,

    // Configuration
    input  wire [1:0]  chsize,    // 00=8-bit, 01=9-bit, 10=5-bit, 11=6-bit
    input  wire [1:0]  parity,    // 00=None, 01=Even, 02=Odd
    input  wire        sbmode,    // 0=1 stop bit, 1=2 stop bits
    // USART note: polarity is INVERTED relative to the SPI engine that
    // shares MODECFG[20] at the top level. Drive HIGH for conventional
    // UART (LSB-first on the wire); LOW for MSB-first.
    input  wire        msbfirst,  // 0=MSB-first on wire, 1=LSB-first on wire (UART standard)

    // FIFO interface
    output reg         fifo_rd,
    input  wire [DATA_WIDTH-1:0] fifo_rdata,
    input  wire        fifo_empty,

    // Status
    output reg         busy,
    output reg         tx_done,

    // Pad output
    output reg         tx_out
);

    //==========================================================================
    // State Machine
    //==========================================================================
    localparam STATE_IDLE     = 3'd0;
    localparam STATE_START    = 3'd1;
    localparam STATE_DATA     = 3'd2;
    localparam STATE_PARITY   = 3'd3;
    localparam STATE_STOP1    = 3'd4;
    localparam STATE_STOP2    = 3'd5;

    reg [2:0] state;

    //==========================================================================
    // Baud Rate Generator (16x oversampled, same as RX)
    //==========================================================================
    // Ticker fires at clkdiv+1 rate (16x oversample).
    // baud_tick fires every 16 ticks = one bit period.
    wire baud_ticker_en = enable && tx_en &&
                          ((state != STATE_IDLE) || ((state == STATE_IDLE) && !fifo_empty));
    wire baud_tick_x16;

    nc_ticker #(
        .W(16)
    ) u_baud_ticker (
        .clk      (clk),
        .rst_n    (rst_n),
        .en       (baud_ticker_en),
        .clk_div  (clkdiv),
        .tick     (baud_tick_x16)
    );

    // Divide by 16 to get the actual baud rate tick
    reg [3:0] baud_div_cnt;
    reg       baud_tick;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_div_cnt <= 4'd0;
            baud_tick    <= 1'b0;
        end else if (!baud_ticker_en || (state == STATE_IDLE)) begin
            baud_div_cnt <= 4'd0;
            baud_tick    <= 1'b0;
        end else if (baud_tick_x16) begin
            if (baud_div_cnt == 4'd15) begin
                baud_div_cnt <= 4'd0;
                baud_tick    <= 1'b1;
            end else begin
                baud_div_cnt <= baud_div_cnt + 1'b1;
                baud_tick    <= 1'b0;
            end
        end else begin
            baud_tick <= 1'b0;
        end
    end

    //==========================================================================
    // Data Transmission Logic
    //==========================================================================
    // Determine data width based on chsize
    reg [3:0] data_bits;
    reg [3:0] bit_counter;
    reg [8:0] tx_shift_reg;
    reg parity_bit;

    always @* begin
        case (chsize)
            2'b00: data_bits = 4'd8;   // 8-bit
            2'b01: data_bits = 4'd9;   // 9-bit
            2'b10: data_bits = 4'd5;   // 5-bit
            2'b11: data_bits = 4'd6;   // 6-bit
        endcase
    end

    //==========================================================================
    // Parity Calculation
    //==========================================================================
    // Parity is computed over the active character width.
    reg parity_data_xor;
    always @(*) begin
        case (chsize)
            2'b01: parity_data_xor = ^fifo_rdata[8:0];
            2'b10: parity_data_xor = ^fifo_rdata[4:0];
            2'b11: parity_data_xor = ^fifo_rdata[5:0];
            default: parity_data_xor = ^fifo_rdata[7:0];
        endcase
    end

    //==========================================================================
    // State Machine
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            bit_counter <= 4'd0;
            tx_shift_reg <= 9'h0;
            parity_bit <= 1'b0;
            busy <= 1'b0;
            tx_done <= 1'b0;
            tx_out <= 1'b1;
            fifo_rd <= 1'b0;
        end else begin
            // Default values
            fifo_rd <= 1'b0;
            tx_done <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    tx_out <= 1'b1;  // Idle high
                    if (enable && tx_en && !fifo_empty) begin
                        // Load data from FIFO
                        tx_shift_reg <= fifo_rdata[8:0];
                        fifo_rd <= 1'b1;
                        // Calculate parity inline
                        if (parity == 2'b01)  // Even parity
                            parity_bit <= ~parity_data_xor;
                        else if (parity == 2'b10)  // Odd parity
                            parity_bit <= parity_data_xor;
                        else
                            parity_bit <= 1'b0;
                        bit_counter <= 4'd0;
                        busy <= 1'b1;
                        state <= STATE_START;
                    end else begin
                        busy <= 1'b0;
                    end
                end

                STATE_START: begin
                    tx_out <= 1'b0;  // Start bit
                    if (baud_tick) begin
                        state <= STATE_DATA;
                    end
                end

                STATE_DATA: begin
                    if (baud_tick) begin
                        // Transmit data bit
                        if (msbfirst) begin
                            tx_out <= tx_shift_reg[data_bits - 1];
                            tx_shift_reg <= {tx_shift_reg[7:0], 1'b0};
                        end else begin
                            tx_out <= tx_shift_reg[0];
                            tx_shift_reg <= {1'b0, tx_shift_reg[8:1]};
                        end

                        if (bit_counter == data_bits - 1) begin
                            if (parity != 2'b00)
                                state <= STATE_PARITY;
                            else
                                state <= STATE_STOP1;
                        end
                        bit_counter <= bit_counter + 1'b1;
                    end
                end

                STATE_PARITY: begin
                    if (baud_tick) begin
                        tx_out <= parity_bit;
                        state <= STATE_STOP1;
                    end
                end

                STATE_STOP1: begin
                    tx_out <= 1'b1;  // Stop bit
                    if (baud_tick) begin
                        if (sbmode)
                            state <= STATE_STOP2;
                        else begin
                            state <= STATE_IDLE;
                            tx_done <= 1'b1;
                        end
                    end
                end

                STATE_STOP2: begin
                    tx_out <= 1'b1;  // Second stop bit
                    if (baud_tick) begin
                        state <= STATE_IDLE;
                        tx_done <= 1'b1;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
