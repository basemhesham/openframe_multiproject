`timescale 1ns/1ps

//==============================================================================
// Copyright (c) 2025-2026 nativechips.ai
// Author: Mohamed Shalan <shalan@nativechips.ai>
// SPDX-License-Identifier: Apache-2.0
//==============================================================================

`default_nettype none

//------------------------------------------------------------------------------
// nc_sercom_spi: SPI Master Transceiver
// Supports CPOL, CPHA, MSB/LSB first, configurable frame size (8/16/32-bit)
//
// SPI Mode Summary (CPOL/CPHA):
//   Mode 0 (0/0): Sample on rising, change on falling. SCK idles low.
//   Mode 1 (0/1): Sample on falling, change on rising. SCK idles low.
//   Mode 2 (1/0): Sample on falling, change on rising. SCK idles high.
//   Mode 3 (1/1): Sample on rising, change on falling. SCK idles high.
//------------------------------------------------------------------------------
module nc_sercom_spi #(
    parameter FIFO_DEPTH = 4,
    parameter DATA_WIDTH = 32
)(
    input  wire        clk,
    input  wire        rst_n,

    // Control
    input  wire        enable,
    input  wire        tx_en,
    input  wire        rx_en,
    input  wire [15:0] clkdiv,

    // Configuration
    input  wire        cpol,      // Clock polarity
    input  wire        cpha,      // Clock phase
    input  wire        msbfirst,  // 0=LSB first, 1=MSB first (note: inverted naming)
    input  wire [1:0]  framesize, // 00=8-bit, 01=16-bit, 10=32-bit

    // FIFO interface
    output reg         tx_fifo_rd,
    input  wire [DATA_WIDTH-1:0] tx_fifo_rdata,
    input  wire        tx_fifo_empty,

    output reg         rx_fifo_wr,
    output reg [DATA_WIDTH-1:0] rx_fifo_wdata,
    input  wire        rx_fifo_full,

    // Chip select
    input  wire [3:0]  cs_mask,
    output wire [3:0]  cs_n_o,

    // Status
    output reg         busy,
    output reg         tx_done,

    // Split pad interface
    output wire        sck_out_o,
    output wire        sck_oe_o,
    output wire        mosi_out_o,
    output wire        mosi_oe_o,
    input  wire        miso_in_i
);

    //==========================================================================
    // MISO synchronizer (CDC)
    //==========================================================================
    // miso_in_i comes from an external pad asynchronous to PCLK. Sampling
    // it straight into the rx shift register is a metastability hazard.
    // Use the same 2-FF synchronizer pattern that nc_sercom_usart_rx.v
    // and nc_sercom_i2c.v already apply to their async inputs.
    wire miso_sync;
    nc_sync #(
        .NUM_STAGES(2)
    ) u_miso_sync (
        .clk   (clk),
        .rst_n (rst_n),
        .in    (miso_in_i),
        .out   (miso_sync)
    );

    //==========================================================================
    // Frame Size Configuration
    //==========================================================================
    reg [5:0] bit_count;
    reg [5:0] bit_counter;

    always @(*) begin
        case (framesize)
            2'b00: bit_count = 6'd8;
            2'b01: bit_count = 6'd16;
            2'b10: bit_count = 6'd32;
            default: bit_count = 6'd8;
        endcase
    end

    //==========================================================================
    // State Machine
    //==========================================================================
    localparam STATE_IDLE     = 2'd0;
    localparam STATE_TRANSFER = 2'd1;
    localparam STATE_HOLD     = 2'd2;

    reg [1:0] state;

    //==========================================================================
    // Clock Generation — half-period ticker
    //==========================================================================
    // sck_edge fires every clkdiv+1 cycles = one half-period of SCK.
    // SCK toggles on each sck_edge.
    reg [15:0] clk_counter;
    reg sck_internal;
    wire sck_edge = (clk_counter == 16'h0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_counter <= 16'h0;
            sck_internal <= 1'b0;
        end else if (enable) begin
            if (state == STATE_IDLE) begin
                sck_internal <= cpol;
                clk_counter <= clkdiv;
            end else if (sck_edge) begin
                sck_internal <= ~sck_internal;
                clk_counter <= clkdiv;
            end else begin
                clk_counter <= clk_counter - 1'b1;
            end
        end else begin
            sck_internal <= cpol;
            clk_counter <= clkdiv;
        end
    end

    // Detect rising/falling of internal SCK
    reg sck_prev;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sck_prev <= 1'b0;
        else
            sck_prev <= sck_internal;
    end

    wire sck_rising  = sck_internal && !sck_prev;
    wire sck_falling = !sck_internal && sck_prev;

    // Determine which edge to sample and which to change MOSI
    // Mode 0 (CPOL=0, CPHA=0): sample on rising, change on falling
    // Mode 1 (CPOL=0, CPHA=1): sample on falling, change on rising
    // Mode 2 (CPOL=1, CPHA=0): sample on falling, change on rising
    // Mode 3 (CPOL=1, CPHA=1): sample on rising, change on falling
    wire sample_edge = (cpol ^ cpha) ? sck_falling : sck_rising;
    wire change_edge = (cpol ^ cpha) ? sck_rising  : sck_falling;

    // Split pad outputs
    assign sck_out_o = sck_internal;
    assign sck_oe_o  = enable && (state != STATE_IDLE);

    //==========================================================================
    // Shift Registers
    //==========================================================================
    reg [31:0] tx_shift_reg;
    reg [31:0] rx_shift_reg;
    // CPHA=1: the first change_edge in a transfer is the edge that "drives"
    // bit 0 — do not shift on it, otherwise the first MOSI bit is lost.
    // SPI spec: for CPHA=1 the leading edge is the data-drive edge and the
    // trailing edge is the data-sample edge.
    reg first_change_pending;

    //==========================================================================
    // MOSI Output (directly from shift register, changes on change_edge)
    //==========================================================================
    // For MSB-first: output MSB of the active frame width
    reg mosi_bit;
    always @(*) begin
        case (framesize)
            2'b00: mosi_bit = msbfirst ? tx_shift_reg[7]  : tx_shift_reg[0];
            2'b01: mosi_bit = msbfirst ? tx_shift_reg[15] : tx_shift_reg[0];
            2'b10: mosi_bit = msbfirst ? tx_shift_reg[31] : tx_shift_reg[0];
            default: mosi_bit = msbfirst ? tx_shift_reg[7]  : tx_shift_reg[0];
        endcase
    end
    assign mosi_out_o = mosi_bit;
    assign mosi_oe_o  = enable && (state == STATE_TRANSFER);

    //==========================================================================
    // Chip Select Output
    //==========================================================================
    assign cs_n_o = (state != STATE_IDLE) ? ~cs_mask : 4'hF;

    //==========================================================================
    // State Machine
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            bit_counter <= 6'd0;
            tx_shift_reg <= 32'h0;
            rx_shift_reg <= 32'h0;
            tx_fifo_rd <= 1'b0;
            rx_fifo_wr <= 1'b0;
            busy <= 1'b0;
            tx_done <= 1'b0;
            first_change_pending <= 1'b0;
        end else begin
            // Default values
            tx_fifo_rd <= 1'b0;
            rx_fifo_wr <= 1'b0;
            tx_done <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    bit_counter <= 6'd0;
                    busy <= 1'b0;

                    if (enable && tx_en && !tx_fifo_empty) begin
                        // Load TX data from FIFO
                        tx_shift_reg <= tx_fifo_rdata;
                        tx_fifo_rd <= 1'b1;
                        rx_shift_reg <= 32'h0;
                        bit_counter <= 6'd0;
                        busy <= 1'b1;
                        // CPHA=1: the first change_edge drives bit 0 (no shift);
                        // subsequent change_edges shift normally.
                        // CPHA=0: every change_edge shifts.
                        first_change_pending <= cpha;
                        state <= STATE_TRANSFER;
                    end
                end

                STATE_TRANSFER: begin
                    // Sample MISO on sample edge
                    if (sample_edge) begin
                        if (msbfirst)
                            rx_shift_reg <= {rx_shift_reg[30:0], miso_sync};
                        else
                            rx_shift_reg <= {miso_sync, rx_shift_reg[31:1]};

                        if (bit_counter == bit_count - 1) begin
                            state <= STATE_HOLD;
                        end
                        bit_counter <= bit_counter + 1'b1;
                    end

                    // Shift TX on change edge (update MOSI for next bit).
                    // For CPHA=1, the very first change_edge of a transfer
                    // is the edge that drives bit 0 — don't shift on it.
                    if (change_edge) begin
                        if (first_change_pending) begin
                            first_change_pending <= 1'b0;
                        end else begin
                            if (msbfirst)
                                tx_shift_reg <= {tx_shift_reg[30:0], 1'b0};  // MSB out first
                            else
                                tx_shift_reg <= {1'b0, tx_shift_reg[31:1]};  // LSB out first
                        end
                    end
                end

                STATE_HOLD: begin
                    // Transfer received data to RX FIFO
                    if (rx_en && !rx_fifo_full) begin
                        rx_fifo_wdata <= rx_shift_reg;
                        rx_fifo_wr <= 1'b1;
                    end

                    tx_done <= 1'b1;
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
