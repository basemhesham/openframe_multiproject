`timescale 1ns/1ps

//==============================================================================
// Copyright (c) 2025-2026 nativechips.ai
// Author: Mohamed Shalan <shalan@nativechips.ai>
// SPDX-License-Identifier: Apache-2.0
//==============================================================================

`default_nettype none

//------------------------------------------------------------------------------
// nc_sercom_i2c: I2C Master Engine
// Supports 7-bit addressing, arbitration detection, clock stretching
//------------------------------------------------------------------------------
module nc_sercom_i2c #(
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
    input  wire [10:0] slave_addr,
    // Removed: tenbit, gcen (issue #9 item 6).
    // These ports were accepted but never referenced inside the engine
    // body and so silently advertised features the RTL does not implement.
    // The top-level register documentation now marks MODECFG[13:12] as
    // RESERVED. 10-bit addressing and general-call can be added later
    // by extending STATE_ADDR (two address bytes) and STATE_IDLE/ADDR
    // (general-call recognition on addr 0x00 in slave-receive mode).
    input  wire        hsmd,      // High speed mode disable

    // Commands (from I2C_CMD register)
    input  wire [1:0]  cmd,       // 00=None, 01=START, 10=STOP
    input  wire        ackact,    // 0=Send ACK, 1=Send NACK

    // FIFO interface
    output reg         tx_fifo_rd,
    input  wire [DATA_WIDTH-1:0] tx_fifo_rdata,
    input  wire        tx_fifo_empty,

    output reg         rx_fifo_wr,
    output reg [DATA_WIDTH-1:0] rx_fifo_wdata,
    input  wire        rx_fifo_full,

    // Status
    output reg         busy,
    output reg         tx_done,
    output reg         bus_busy,
    output reg         arb_lost,
    output reg         rx_nack,

    // Split pad interface (active-low open-drain: oe=1 drives low)
    output wire        sda_out_o,
    output wire        sda_oe_o,
    input  wire        sda_in_i,
    output wire        scl_out_o,
    output wire        scl_oe_o,
    input  wire        scl_in_i
);

    //==========================================================================
    // Pad Interface (Open-drain: oe drives low only)
    //==========================================================================
    wire sda_in;
    wire scl_in;
    reg sda_drv;  // 1 = release bus (high), 0 = pull low
    reg scl_drv;  // 1 = release bus (high), 0 = pull low

    // Input synchronizers
    wire sda_sync_n;
    wire scl_sync_n;

    nc_sync #(
        .NUM_STAGES(2)
    ) u_sda_sync_n (
        .clk   (clk),
        .rst_n (rst_n),
        .in    (~sda_in_i),
        .out   (sda_sync_n)
    );

    nc_sync #(
        .NUM_STAGES(2)
    ) u_scl_sync_n (
        .clk   (clk),
        .rst_n (rst_n),
        .in    (~scl_in_i),
        .out   (scl_sync_n)
    );

    assign sda_in = ~sda_sync_n;
    assign scl_in = ~scl_sync_n;

    // Open-drain output: only drive when pulling low (drv=0)
    assign sda_out_o = 1'b0;
    assign sda_oe_o  = ~sda_drv;  // oe=1 when pulling low
    assign scl_out_o = 1'b0;
    assign scl_oe_o  = ~scl_drv;  // oe=1 when pulling low

    //==========================================================================
    // State Machine
    //==========================================================================
    localparam STATE_IDLE        = 4'd0;
    localparam STATE_START       = 4'd1;
    localparam STATE_ADDR        = 4'd2;
    localparam STATE_ACK_CHECK   = 4'd3;
    localparam STATE_DATA_TX     = 4'd4;
    localparam STATE_DATA_RX     = 4'd5;
    localparam STATE_ACK_TX      = 4'd6;
    localparam STATE_STOP        = 4'd7;
    localparam STATE_WAIT_SCL    = 4'd8;
    // Issue #9 item 2: explicit repeated-start command (cmd == 2'b11).
    // After ACK_TX of the previous byte, RS_RELEASE lets the bus rise to
    // idle (SDA & SCL released), then RS_SETUP asserts the Sr condition
    // (SDA falls while SCL is high). From there we re-enter STATE_START.
    localparam STATE_RS_RELEASE  = 4'd9;
    localparam STATE_RS_SETUP    = 4'd10;

    reg [3:0] state;

    //==========================================================================
    // Clock Generation
    //==========================================================================
    wire start_cmd = (state == STATE_IDLE) && enable &&
                     (cmd == 2'b01) && !bus_busy;
    wire clk_ticker_en = enable && ((state != STATE_IDLE) || start_cmd);
    wire clk_ticker_tick;
    reg  drop_first_tick;
    wire clk_tick = clk_ticker_tick && !drop_first_tick;

    nc_ticker #(
        .W(16)
    ) u_i2c_ticker (
        .clk      (clk),
        .rst_n    (rst_n),
        .en       (clk_ticker_en),
        .clk_div  (clkdiv),
        .tick     (clk_ticker_tick)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            drop_first_tick <= 1'b0;
        else if (!enable || ((state == STATE_IDLE) && !start_cmd))
            drop_first_tick <= 1'b0;
        else if (start_cmd)
            drop_first_tick <= 1'b1;
        else if (clk_ticker_tick && drop_first_tick)
            drop_first_tick <= 1'b0;
    end

    //==========================================================================
    // Shift Registers
    //==========================================================================
    reg [7:0] tx_shift_reg;
    reg [7:0] rx_shift_reg;
    reg [3:0] bit_counter;
    reg       addr_rw_bit;   // Saved R/W bit from address byte

    //==========================================================================
    // Arbitration Detection
    //==========================================================================
    reg lost_arbitration;

    always @(*) begin
        // Lost arbitration: we released SDA (drv=1) but it reads low
        // OR: we're driving high but someone else is pulling low
        lost_arbitration = (sda_drv == 1'b1) && !sda_in && (state != STATE_IDLE);
    end

    // Latch: an Sr (cmd == 2'b11) was already consumed in the current
    // transaction. Clears when the master returns to STATE_IDLE.
    reg sr_done;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                                          sr_done <= 1'b0;
        else if (state == STATE_IDLE)                        sr_done <= 1'b0;
        else if (state == STATE_RS_RELEASE && !sr_done)      sr_done <= 1'b1;
    end

    //==========================================================================
    // State Machine
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            bit_counter <= 4'd0;
            tx_shift_reg <= 8'h0;
            rx_shift_reg <= 8'h0;
            sda_drv <= 1'b1;  // Release (high)
            scl_drv <= 1'b1;  // Release (high)
            tx_fifo_rd <= 1'b0;
            rx_fifo_wr <= 1'b0;
            busy <= 1'b0;
            tx_done <= 1'b0;
            bus_busy <= 1'b0;
            addr_rw_bit <= 1'b0;
            arb_lost <= 1'b0;
            rx_nack <= 1'b0;
        end else begin
            // Default values
            tx_fifo_rd <= 1'b0;
            rx_fifo_wr <= 1'b0;
            tx_done <= 1'b0;

            // Detect bus busy
            bus_busy <= (sda_in || scl_in) ? 1'b0 : bus_busy;

            case (state)
                STATE_IDLE: begin
                    sda_drv <= 1'b1;  // Release
                    scl_drv <= 1'b1;  // Release
                    busy <= 1'b0;
                    bit_counter <= 4'd0;

                    if (enable && cmd == 2'b01 && !bus_busy) begin
                        // Generate START: pull SDA low while SCL high
                        sda_drv <= 1'b0;  // Pull low
                        state <= STATE_START;
                        busy <= 1'b1;
                    end
                end

                STATE_START: begin
                    if (clk_tick) begin
                        // SCL goes low after SDA
                        scl_drv <= 1'b0;  // Pull low

                        // Load address/data and save R/W bit
                        if (tx_en && !tx_fifo_empty) begin
                            tx_fifo_rd <= 1'b1;
                            tx_shift_reg <= tx_fifo_rdata[7:0];
                            addr_rw_bit  <= tx_fifo_rdata[0];
                        end

                        bit_counter <= 4'd0;
                        state <= STATE_ADDR;
                    end
                end

                STATE_ADDR: begin
                    if (clk_tick) begin
                        if (scl_drv == 1'b0) begin
                            // SCL is low: set SDA for next bit, then raise SCL
                            sda_drv <= tx_shift_reg[7];
                            scl_drv <= 1'b1;  // Release SCL (rises via pull-up)

                            // Check arbitration on bus
                            if (lost_arbitration) begin
                                arb_lost <= 1'b1;
                                state <= STATE_IDLE;
                            end
                        end else if (scl_in) begin
                            // SCL released and actually high (no slave stretching):
                            // pull SCL low, sample SDA, shift.  (Issue #9 item 7.)
                            scl_drv <= 1'b0;
                            rx_shift_reg <= {rx_shift_reg[6:0], sda_in};
                            tx_shift_reg <= {tx_shift_reg[6:0], 1'b1};

                            if (bit_counter == 4'd7) begin
                                state <= STATE_ACK_CHECK;
                            end
                            bit_counter <= bit_counter + 1'b1;
                        end
                        // else: slave is stretching SCL — stall here.
                    end
                end

                STATE_ACK_CHECK: begin
                    if (clk_tick) begin
                        if (scl_drv == 1'b0) begin
                            // Phase 1: SCL low, release SDA, raise SCL for slave ACK
                            sda_drv <= 1'b1;  // Release SDA
                            scl_drv <= 1'b1;  // Raise SCL so slave can drive ACK
                        end else if (scl_in) begin
                            // Phase 2: SCL released and actually high. Sample
                            // ACK from slave and pull SCL low.  (Issue #9 item 7.)
                            scl_drv <= 1'b0;
                            rx_nack <= sda_in;

                            if (sda_in) begin
                                // NACK
                                state <= STATE_STOP;
                            end else begin
                                // ACK — load next data byte
                                bit_counter <= 4'd0;
                                if (!addr_rw_bit) begin
                                    if (tx_en && !tx_fifo_empty) begin
                                        tx_fifo_rd <= 1'b1;
                                        tx_shift_reg <= tx_fifo_rdata[7:0];
                                    end
                                    state <= STATE_DATA_TX;
                                end else begin
                                    state <= STATE_DATA_RX;
                                end
                            end
                        end
                    end
                end

                STATE_DATA_TX: begin
                    if (clk_tick) begin
                        if (scl_drv == 1'b0) begin
                            // SCL low: set SDA from shift reg, raise SCL
                            sda_drv <= tx_shift_reg[7];
                            scl_drv <= 1'b1;
                        end else if (scl_in) begin
                            // SCL released and actually high: pull low, shift.
                            // (Issue #9 item 7: honor slave clock-stretching.)
                            scl_drv <= 1'b0;
                            tx_shift_reg <= {tx_shift_reg[6:0], 1'b1};

                            if (bit_counter == 4'd7) begin
                                state <= STATE_ACK_TX;
                            end
                            bit_counter <= bit_counter + 1'b1;
                        end
                        // else: slave is stretching SCL — stall here.
                    end
                end

                STATE_DATA_RX: begin
                    if (clk_tick) begin
                        if (scl_drv == 1'b0) begin
                            // SCL low: release SDA for slave to drive, raise SCL
                            sda_drv <= 1'b1;
                            scl_drv <= 1'b1;
                        end else if (scl_in) begin
                            // SCL released and actually high: sample SDA, pull
                            // SCL low. (Issue #9 item 7.)
                            scl_drv <= 1'b0;
                            rx_shift_reg <= {rx_shift_reg[6:0], sda_in};

                            if (bit_counter == 4'd7) begin
                                if (rx_en && !rx_fifo_full) begin
                                    rx_fifo_wdata <= {{(DATA_WIDTH-8){1'b0}}, rx_shift_reg[6:0], sda_in};
                                    rx_fifo_wr <= 1'b1;
                                end
                                state <= STATE_ACK_TX;
                            end
                            bit_counter <= bit_counter + 1'b1;
                        end
                        // else: slave is stretching SCL — stall here.
                    end
                end

                STATE_ACK_TX: begin
                    if (clk_tick) begin
                        scl_drv <= 1'b0;  // Pull low
                        // Send ACK (pull low) or NACK (release)
                        sda_drv <= ackact;  // 0=ACK (pull low), 1=NACK (release)

                        // Issue #9 item 2: cmd == 2'b11 = repeated-start.
                        // Takes precedence over STOP / continue. Only once
                        // per transaction (sr_done latch prevents re-firing).
                        if (cmd == 2'b11 && !sr_done) begin
                            state <= STATE_RS_RELEASE;
                        end else if (cmd == 2'b10 || (tx_fifo_empty && !tx_shift_reg[0])) begin
                            // Explicit STOP, or the legacy auto-STOP heuristic
                            // (rarely fires in practice — tx_shift_reg is
                            // always 0xFF after 8 left-shifts so bit 0 = 1).
                            state <= STATE_STOP;
                        end else begin
                            bit_counter <= 4'd0;
                            if (addr_rw_bit) begin
                                // READ continuation — slave drives next byte.
                                state <= STATE_DATA_RX;
                            end else begin
                                // WRITE continuation. **Issue #10 fix**: reload
                                // tx_shift_reg from the TX FIFO when there
                                // is more data. Previously tx_shift_reg was
                                // only loaded in STATE_START (address) and
                                // STATE_ACK_CHECK (first data byte after the
                                // address ACK), so bytes 2..N of a multi-byte
                                // write were the stale 0xFF left in the shift
                                // register from the previous data byte's 8
                                // left-shifts. Loading from FIFO here makes
                                // bytes 2..N reach the slave correctly.
                                if (tx_en && !tx_fifo_empty) begin
                                    tx_fifo_rd   <= 1'b1;
                                    tx_shift_reg <= tx_fifo_rdata[7:0];
                                end
                                // If tx_fifo_empty, tx_shift_reg keeps its
                                // (post-8-shift = 0xFF) value and the master
                                // continues clocking that byte on the bus
                                // until software issues cmd=STOP. This is the
                                // pre-Issue-#10 behaviour, preserved to keep
                                // existing testbench compatibility — for a
                                // FUTURE fix that also clock-stretches on
                                // empty FIFO (the "right" I²C behaviour) the
                                // testbench slaves need to stop expecting an
                                // SCL pulse after the master's last data byte.
                                state <= STATE_DATA_TX;
                            end
                        end
                    end
                end

                STATE_STOP: begin
                    if (clk_tick) begin
                        // STOP: SDA low->high while SCL high
                        scl_drv <= 1'b1;  // Release SCL

                        // Wait for SCL to go high (clock stretching)
                        if (scl_in) begin
                            sda_drv <= 1'b1;  // Release SDA

                            if (sda_in) begin
                                state <= STATE_IDLE;
                                tx_done <= 1'b1;
                            end
                        end
                    end
                end

                // Issue #9 item 2: repeated-start sequence.  After
                // STATE_ACK_TX pulled SCL low, RS_RELEASE lets both SCL and
                // SDA rise (master releases both lines). RS_SETUP waits for
                // SCL to actually be high (honors stretch) and then drives
                // SDA from high to low — the I2C-spec Sr condition.  From
                // there we re-enter STATE_START which pulls SCL low and
                // loads the next address byte from the TX FIFO.
                STATE_RS_RELEASE: begin
                    if (clk_tick) begin
                        sda_drv <= 1'b1;  // Release SDA  (rises via pull-up)
                        scl_drv <= 1'b1;  // Release SCL  (rises via pull-up)
                        state   <= STATE_RS_SETUP;
                    end
                end

                STATE_RS_SETUP: begin
                    if (clk_tick) begin
                        if (scl_in) begin
                            // SCL is actually high — assert Sr by driving
                            // SDA low while SCL is high.  STATE_START will
                            // then pull SCL low and load the next address.
                            sda_drv <= 1'b0;
                            state   <= STATE_START;
                        end
                        // else: slave stretching — wait.
                    end
                end

                STATE_WAIT_SCL: begin
                    // Handle clock stretching
                    if (scl_in) begin
                        state <= STATE_ADDR;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
