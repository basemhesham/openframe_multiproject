`timescale 1ns/1ps

//==============================================================================
// Copyright (c) 2025-2026 nativechips.ai
// Author: Mohamed Shalan <shalan@nativechips.ai>
// SPDX-License-Identifier: Apache-2.0
//==============================================================================

`default_nettype none

//------------------------------------------------------------------------------
// nc_sercom_usart_rx: USART Receiver
// Supports configurable data bits (5-9), parity, stop bits
// Oversampling: 16x, 8x, or 3x
//------------------------------------------------------------------------------
module nc_sercom_usart_rx #(
    parameter FIFO_DEPTH = 4,
    parameter DATA_WIDTH = 32
)(
    input  wire        clk,
    input  wire        rst_n,

    // Control
    input  wire        enable,
    input  wire        rx_en,
    input  wire [15:0] clkdiv,

    // Configuration
    input  wire [1:0]  chsize,    // 00=8-bit, 01=9-bit, 10=5-bit, 11=6-bit
    input  wire [1:0]  parity,   // 00=None, 01=Even, 10=Odd
    // USART note: this signal's polarity is INVERTED relative to the SPI
    // engine's `msbfirst` input that shares the same MODECFG[20] bit at the
    // top level (rtl/nc_sercom.v:112). For a conventional UART (LSB-first
    // on the wire) drive this HIGH; for an MSB-first wire format drive LOW.
    // Implementation rationale: with 1 the shift register inserts new bits
    // at the high position and shifts right, leaving the first-received
    // bit in bit 0 of the final byte (LSB-first reception convention).
    input  wire        msbfirst, // 0=MSB-first on wire, 1=LSB-first on wire (UART standard)
    input  wire [1:0]  sampr,    // 00=16x, 01=8x, 10=3x

    // FIFO interface
    output reg         fifo_wr,
    output reg [DATA_WIDTH-1:0] fifo_wdata,
    input  wire        fifo_full,

    // Status
    output reg         busy,
    output reg         rx_ne,     // RX not empty

    // Pad input
    input  wire        rx_in,

    // Error flags
    output reg         frame_err,
    output reg         parity_err,
    output reg         break_det,
    output reg         bufovf_pulse
);

    //==========================================================================
    // Oversampling Configuration
    //==========================================================================
    reg [3:0] sample_point_mid;
    reg [3:0] sample_point_max;

    always @(*) begin
        case (sampr)
            2'b00: begin  // 16x oversample
                sample_point_mid = 4'd8;
                sample_point_max = 4'd15;
            end
            2'b01: begin  // 8x oversample
                sample_point_mid = 4'd4;
                sample_point_max = 4'd7;
            end
            2'b10: begin  // 3x oversample
                sample_point_mid = 4'd1;
                sample_point_max = 4'd2;
            end
            default: begin
                sample_point_mid = 4'd8;
                sample_point_max = 4'd15;
            end
        endcase
    end

    //==========================================================================
    // State Machine
    //==========================================================================
    localparam STATE_IDLE     = 3'd0;
    localparam STATE_START    = 3'd1;
    localparam STATE_DATA     = 3'd2;
    localparam STATE_PARITY   = 3'd3;
    localparam STATE_STOP     = 3'd4;

    reg [2:0] state;

    //==========================================================================
    // Baud Rate Generator with Oversampling
    //==========================================================================
    // Arm ticker when start edge is detected so the first strobe in START
    // lands on the same cycle as the legacy local counter implementation.
    wire start_falling;
    reg start_detected;  // Forward declaration for Verilog-2005 compliance
    wire sample_ticker_en = enable && rx_en &&
                            ((state != STATE_IDLE) ||
                             ((state == STATE_IDLE) && start_falling && !start_detected));
    reg [3:0] oversample_cnt;
    wire sample_strobe;
    wire sample_tick = sample_strobe && (oversample_cnt == sample_point_max);
    wire sample_mid = sample_strobe && (oversample_cnt == sample_point_mid);

    nc_ticker #(
        .W(16)
    ) u_sample_ticker (
        .clk      (clk),
        .rst_n    (rst_n),
        .en       (sample_ticker_en),
        .clk_div  (clkdiv),
        .tick     (sample_strobe)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            oversample_cnt <= 4'h0;
        end else if (!enable || !rx_en || (state == STATE_IDLE)) begin
            oversample_cnt <= 4'h0;
        end else if (sample_strobe) begin
            if (sample_tick) begin
                oversample_cnt <= 4'h0;
            end else begin
                oversample_cnt <= oversample_cnt + 1'b1;
            end
        end
    end

    //==========================================================================
    // Data Reception Logic
    //==========================================================================
    reg [3:0] data_bits;
    reg [3:0] bit_counter;
    reg [8:0] rx_shift_reg;
    reg parity_calc;
    reg parity_bit;
    // start_detected declared above (forward declaration for Verilog-2005)

    // Synchronizer for RX input (reduce metastability)
    // Use inversion so synchronized RX idles high after reset.
    wire rx_sync_n;
    wire rx_sync;
    reg  rx_sync_d;

    nc_sync #(
        .NUM_STAGES(2)
    ) u_rx_sync_n (
        .clk   (clk),
        .rst_n (rst_n),
        .in    (~rx_in),
        .out   (rx_sync_n)
    );

    assign rx_sync = ~rx_sync_n;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rx_sync_d <= 1'b1;
        else
            rx_sync_d <= rx_sync;
    end

    // Edge detection for start bit
    assign start_falling = (rx_sync_d && !rx_sync);

    always @* begin
        case (chsize)
            2'b00: data_bits = 4'd8;   // 8-bit
            2'b01: data_bits = 4'd9;   // 9-bit
            2'b10: data_bits = 4'd5;   // 5-bit
            2'b11: data_bits = 4'd6;   // 6-bit
        endcase
    end

    //==========================================================================
    // State Machine
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            bit_counter <= 4'd0;
            rx_shift_reg <= 9'h0;
            parity_calc <= 1'b0;
            parity_bit <= 1'b0;
            busy <= 1'b0;
            rx_ne <= 1'b0;
            fifo_wr <= 1'b0;
            frame_err <= 1'b0;
            parity_err <= 1'b0;
            break_det <= 1'b0;
            bufovf_pulse <= 1'b0;
            start_detected <= 1'b0;
        end else begin
            // Default values
            fifo_wr <= 1'b0;
            frame_err <= 1'b0;
            parity_err <= 1'b0;
            break_det <= 1'b0;
            bufovf_pulse <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    rx_ne <= 1'b0;
                    if (enable && rx_en && start_falling && !start_detected) begin
                        start_detected <= 1'b1;
                        state <= STATE_START;
                    end
                end

                STATE_START: begin
                    if (sample_mid) begin
                        // Validate start bit at mid-point (still low)
                        if (rx_sync) begin
                            // False start bit, return to idle
                            state <= STATE_IDLE;
                            start_detected <= 1'b0;
                        end
                    end
                    if (sample_tick) begin
                        // Transition to DATA at bit boundary so bit_counter
                        // stays aligned with actual data bit periods.
                        bit_counter <= 4'd0;
                        rx_shift_reg <= 9'h0;
                        parity_calc <= 1'b0;
                        state <= STATE_DATA;
                    end
                end

                STATE_DATA: begin
                    if (sample_mid) begin
                        // Sample data bit
                        if (msbfirst) begin
                            rx_shift_reg <= {rx_sync, rx_shift_reg[8:1]};
                        end else begin
                            rx_shift_reg <= {rx_shift_reg[7:0], rx_sync};
                        end
                        parity_calc <= parity_calc ^ rx_sync;
                    end

                    if (sample_tick) begin
                        if (bit_counter == data_bits - 1) begin
                            if (parity != 2'b00)
                                state <= STATE_PARITY;
                            else
                                state <= STATE_STOP;
                        end
                        bit_counter <= bit_counter + 1'b1;
                    end
                end

                STATE_PARITY: begin
                    if (sample_mid) begin
                        parity_bit <= rx_sync;
                    end
                    if (sample_tick) begin
                        // Check parity
                        if (parity == 2'b01) begin  // Even parity
                            parity_err <= (parity_calc != rx_sync);
                        end else if (parity == 2'b10) begin  // Odd parity
                            parity_err <= (parity_calc == rx_sync);
                        end
                        state <= STATE_STOP;
                    end
                end

                STATE_STOP: begin
                    if (sample_mid) begin
                        // Check stop bit (must be high)
                        if (!rx_sync) begin
                            frame_err <= 1'b1;
                            // Check for break (all zeros including start)
                            if (!rx_sync_d && !rx_sync)
                                break_det <= 1'b1;
                        end
                    end

                    if (sample_tick) begin
                        // Transfer data to FIFO
                        // For msbfirst=1 (LSB-first wire), bits enter at
                        // shift_reg[8] and shift right. After `data_bits` shifts
                        // the valid byte occupies shift_reg[8 -: data_bits], so
                        // right-shift by (9 - data_bits) to align bit0 at [0].
                        // For msbfirst=0 (MSB-first wire), bits enter at [0]
                        // and shift left; valid byte is already aligned at
                        // [data_bits-1:0].
                        if (!fifo_full && !frame_err) begin
                            if (msbfirst)
                                fifo_wdata <= {{(DATA_WIDTH-9){1'b0}},
                                               rx_shift_reg >> (4'd9 - data_bits)};
                            else
                                fifo_wdata <= {{(DATA_WIDTH-9){1'b0}}, rx_shift_reg};
                            fifo_wr <= 1'b1;
                            rx_ne <= 1'b1;
                        end else if (fifo_full && !frame_err) begin
                            // Byte completed but FIFO is full: pulse overflow.
                            bufovf_pulse <= 1'b1;
                        end
                        state <= STATE_IDLE;
                        start_detected <= 1'b0;
                    end
                end

                default: state <= STATE_IDLE;
            endcase

            busy <= (state != STATE_IDLE);
        end
    end

endmodule

`default_nettype wire
