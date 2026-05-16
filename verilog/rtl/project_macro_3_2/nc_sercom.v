`timescale 1ns/1ps

//==============================================================================
// Copyright (c) 2025-2026 nativechips.ai
// Author: Mohamed Shalan <shalan@nativechips.ai>
// SPDX-License-Identifier: Apache-2.0
//==============================================================================

`default_nettype none

//------------------------------------------------------------------------------
// nc_sercom: Serial Communication Interface (SERCOM)
// Multi-protocol serial peripheral: USART, SPI, I2C
//------------------------------------------------------------------------------
module nc_sercom #(
    parameter FIFO_DEPTH = 4  // TX/RX FIFO depth (default: 4 entries)
) (
    // APB3 Interface
    input  wire        PCLK,
    input  wire        PRESETn,
    input  wire [11:0] PADDR,
    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [31:0] PWDATA,
    output wire [31:0] PRDATA,
    output wire        PREADY,
    output wire        PSLVERR,

    // Interrupt
    output wire        irq_o,

    // DMA Requests
    output wire        dma_tx_req_o,
    output wire        dma_rx_req_o,

    // SERCOM Pads (split interface for SoC pad ring integration)
    output wire [5:0]  pad_out_o,
    output wire [5:0]  pad_oe_o,
    input  wire [5:0]  pad_in_i
);

    //==========================================================================
    // Register Address Definitions (CSR Layout Compliant)
    //==========================================================================
    // Standard front-end (0x000-0x0FF)
    localparam [11:0] ADDR_CR        = 12'h000;
    localparam [11:0] ADDR_SR        = 12'h004;
    localparam [11:0] ADDR_DR        = 12'h008;
    localparam [11:0] ADDR_IM        = 12'h020;
    localparam [11:0] ADDR_RIS       = 12'h024;
    localparam [11:0] ADDR_MIS       = 12'h028;
    localparam [11:0] ADDR_ICR       = 12'h02C;
    localparam [11:0] ADDR_DMACR     = 12'h040;
    localparam [11:0] ADDR_TXLVL     = 12'h044;
    localparam [11:0] ADDR_RXLVL     = 12'h048;
    localparam [11:0] ADDR_FIFOCTRL  = 12'h050;
    localparam [11:0] ADDR_FIFOSTR   = 12'h054;
    // Extension space (0x100+) — protocol-specific registers
    localparam [11:0] ADDR_MODECFG       = 12'h100;
    localparam [11:0] ADDR_TIMING        = 12'h104;
    localparam [11:0] ADDR_ADDR          = 12'h108;
    localparam [11:0] ADDR_FRAME         = 12'h10C;
    localparam [11:0] ADDR_I2C_CMD       = 12'h110;
    localparam [11:0] ADDR_I2C_STATUS    = 12'h114;
    localparam [11:0] ADDR_SPI_CS        = 12'h118;
    localparam [11:0] ADDR_SPI_CFG       = 12'h11C;
    localparam [11:0] ADDR_USART_STATUS  = 12'h120;
    localparam [11:0] ADDR_USART_RXTO    = 12'h124;
    // Discovery registers
    localparam [11:0] ADDR_FEATURE   = 12'hFF8;
    localparam [11:0] ADDR_ID        = 12'hFFC;

    localparam [31:0] ID_VALUE      = 32'h5345_5243;  // "SERC"
    localparam [31:0] FEATURE_VALUE = 32'h0000_000F;  // USART+SPI+I2C+DMA

    //==========================================================================
    // APB Transaction Signals
    //==========================================================================
    wire apb_write = PSEL & PENABLE & PWRITE;
    wire apb_read  = PSEL & PENABLE & ~PWRITE;
    wire [11:0] word_addr = PADDR;  // Full address for comparison

    //==========================================================================
    // Registered Control and Configuration Signals
    //==========================================================================
    reg [31:0] cr_reg;
    reg [31:0] modecfg_reg;
    reg [31:0] timing_reg;
    reg [31:0] addr_reg;
    reg [31:0] frame_reg;
    reg [31:0] im_reg;
    reg [31:0] dmacr_reg;
    reg [31:0] fifoctrl_reg;
    reg [31:0] i2c_cmd_reg;
    reg [31:0] spi_cs_reg;
    reg [31:0] spi_cfg_reg;
    reg [31:0] usart_rxto_reg;

    // CR bit layout (CSR compliant):
    //   [0]=EN, [1]=SRST, [3:2]=MODE, [4]=LPMEN, [5]=DBGEN, [8]=TXEN, [9]=RXEN
    wire periph_en    = cr_reg[0];
    wire sw_reset     = cr_reg[1];
    wire [1:0] mode   = cr_reg[3:2];
    wire lpmen        = cr_reg[4];
    wire dbgen        = cr_reg[5];
    wire tx_en        = cr_reg[8];
    wire rx_en        = cr_reg[9];

    // MODECFG configuration
    wire loopback     = modecfg_reg[23];
    // NOTE: bit 20 is interpreted differently by each protocol engine.
    //   SPI engine : 1 = MSB-first  on wire (SPI standard "MSB first")
    //   USART eng. : 1 = LSB-first  on wire (UART standard frame order)
    // So `MODECFG[20]=1` selects the conventional bit order for both
    // protocols. The polarity inversion lives inside the USART engine
    // (see rtl/nc_sercom_usart_rx.v:31, _tx.v:31). Do not "fix" this by
    // inverting at the top level — it would break the UART standard
    // default behaviour silicon currently exposes.
    wire msbfirst     = modecfg_reg[20];
    wire [1:0] sampr  = modecfg_reg[7:6];
    wire [1:0] dopo   = modecfg_reg[15:14];
    wire [1:0] dipo   = modecfg_reg[13:12];
    wire [1:0] txpo   = modecfg_reg[11:10];
    wire [1:0] rxpo   = modecfg_reg[9:8];

    // Frame configuration (USART)
    wire [1:0] chsize = frame_reg[1:0];
    wire [1:0] parity = frame_reg[5:4];
    wire sbmode      = frame_reg[6];

    // DMA signals
    wire tx_dma_en    = dmacr_reg[0];
    wire rx_dma_en    = dmacr_reg[1];
    wire [3:0] tx_dma_th = dmacr_reg[7:4];
    wire [7:0] rx_dma_th = dmacr_reg[23:16];

    // I2C command signals
    wire [1:0] i2c_cmd   = i2c_cmd_reg[1:0];
    wire i2c_ackact      = i2c_cmd_reg[2];

    //==========================================================================
    // FIFO Implementation (using nc_common/nc_fifo)
    //==========================================================================
    // nc_fifo depth is 2^AW, so AW is chosen as ceil(log2(FIFO_DEPTH)).
    localparam FIFO_PTR_W  = (FIFO_DEPTH <= 2)  ? 1 :
                             (FIFO_DEPTH <= 4)  ? 2 :
                             (FIFO_DEPTH <= 8)  ? 3 :
                             (FIFO_DEPTH <= 16) ? 4 : 5;

    function [4:0] lvl5;
        input [FIFO_PTR_W:0] cnt;
        begin
            lvl5 = {{(5-(FIFO_PTR_W+1)){1'b0}}, cnt};
        end
    endfunction
    function [7:0] cnt8;
        input [FIFO_PTR_W:0] cnt;
        begin
            cnt8 = {{(8-(FIFO_PTR_W+1)){1'b0}}, cnt};
        end
    endfunction

    // TX FIFO
    wire tx_fifo_wr;
    wire tx_fifo_rd;
    wire tx_fifo_flush;
    wire [31:0] tx_fifo_wdata;
    wire tx_fifo_empty;
    wire tx_fifo_full;
    wire [31:0] tx_fifo_rdata;
    wire [FIFO_PTR_W:0] tx_lvl_raw;
    wire [4:0] tx_lvl = lvl5(tx_lvl_raw);

    // RX FIFO
    wire rx_fifo_wr;
    wire rx_fifo_rd;
    wire rx_fifo_flush;
    wire [31:0] rx_fifo_wdata;
    wire rx_fifo_empty;
    wire rx_fifo_full;
    wire [31:0] rx_fifo_rdata;
    wire [FIFO_PTR_W:0] rx_lvl_raw;
    wire [4:0] rx_lvl = lvl5(rx_lvl_raw);

    nc_fifo #(
        .DW(32),
        .AW(FIFO_PTR_W)
    ) u_tx_fifo (
        .clk   (PCLK),
        .rst_n (PRESETn),
        .rd    (tx_fifo_rd),
        .wr    (tx_fifo_wr),
        .flush (tx_fifo_flush),
        .wdata (tx_fifo_wdata),
        .empty (tx_fifo_empty),
        .full  (tx_fifo_full),
        .rdata (tx_fifo_rdata),
        .level (tx_lvl_raw)
    );

    nc_fifo #(
        .DW(32),
        .AW(FIFO_PTR_W)
    ) u_rx_fifo (
        .clk   (PCLK),
        .rst_n (PRESETn),
        .rd    (rx_fifo_rd),
        .wr    (rx_fifo_wr),
        .flush (rx_fifo_flush),
        .wdata (rx_fifo_wdata),
        .empty (rx_fifo_empty),
        .full  (rx_fifo_full),
        .rdata (rx_fifo_rdata),
        .level (rx_lvl_raw)
    );

    //==========================================================================
    // Status Register Bits
    //==========================================================================
    reg sr_idle;
    reg sr_err;
    reg sr_busy;
    reg sr_tc;
    wire sr_txe  = tx_fifo_empty;
    wire sr_rxne = ~rx_fifo_empty;

    // USART-specific status
    reg usart_perr;
    reg usart_ferr;
    wire usart_coll = 1'b0;  // No collision detect in master-only simplex
    reg usart_bufovf;
    reg usart_brk;

    // I2C-specific status (i2c_busy_engine declared in Protocol Engine section)
    reg i2c_arblost;
    reg i2c_rxnack;

    //==========================================================================
    // Interrupt Flags
    //==========================================================================
    reg tx_ris_q;
    reg rx_ris_q;
    reg idle_ris_q;
    reg err_ris_q;
    reg tc_ris_q;

    // Masked interrupts
    wire tx_mis  = tx_ris_q  & im_reg[0];
    wire rx_mis  = rx_ris_q  & im_reg[1];
    wire idle_mis= idle_ris_q& im_reg[3];
    wire err_mis = err_ris_q & im_reg[4];
    wire tc_mis  = tc_ris_q  & im_reg[6];

    // Combined interrupt
    assign irq_o = tx_mis | rx_mis | idle_mis | err_mis | tc_mis;

    //==========================================================================
    // DMA Requests
    //==========================================================================
    assign dma_tx_req_o = tx_dma_en && (cnt8(tx_lvl_raw) <= {4'h0, tx_dma_th});
    assign dma_rx_req_o = rx_dma_en && (cnt8(rx_lvl_raw) >= rx_dma_th);

    //==========================================================================
    // Protocol Engine Interconnect Signals
    //==========================================================================

    // USART TX
    wire usart_tx_busy;
    wire usart_tx_done;
    wire usart_tx_fifo_rd;
    wire usart_tx_out;

    // USART RX
    wire usart_rx_busy;
    wire usart_rx_fifo_wr;
    wire [31:0] usart_rx_fifo_wdata;
    wire usart_rx_ne;
    wire usart_frame_err;
    wire usart_parity_err;
    wire usart_break_det;
    wire usart_bufovf_pulse;

    // SPI
    wire spi_busy;
    wire spi_tx_done;
    wire spi_tx_fifo_rd;
    wire spi_rx_fifo_wr;
    wire [31:0] spi_rx_fifo_wdata;
    wire [3:0] spi_cs_n;
    wire spi_sck_out, spi_sck_oe;
    wire spi_mosi_out, spi_mosi_oe;

    // I2C
    wire i2c_busy_engine;
    wire i2c_tx_done;
    wire i2c_tx_fifo_rd;
    wire i2c_rx_fifo_wr;
    wire [31:0] i2c_rx_fifo_wdata;
    wire i2c_sda_out, i2c_sda_oe;
    wire i2c_scl_out, i2c_scl_oe;
    wire i2c_bus_busy_engine;
    wire i2c_arb_lost_engine;
    wire i2c_rx_nack_engine;

    //==========================================================================
    // FIFO Interconnect
    //==========================================================================
    assign tx_fifo_wr = apb_write && (word_addr == ADDR_DR);
    assign tx_fifo_wdata = PWDATA;
    assign tx_fifo_rd = ((mode == 2'b00) && usart_tx_fifo_rd) ||
                        ((mode == 2'b01) && spi_tx_fifo_rd) ||
                        ((mode == 2'b10) && i2c_tx_fifo_rd);
    assign tx_fifo_flush = (apb_write && (word_addr == ADDR_FIFOCTRL) && PWDATA[9]) ||
                           sw_reset;

    // RX FIFO read: capture data before pointer advances.
    // The FIFO's rdata is combinational from array_reg[r_ptr_reg].
    // We latch it on the setup phase of the APB read (PSEL & ~PENABLE)
    // so it's stable when PRDATA is sampled on the access phase.
    reg [31:0] rx_dr_latch;
    always @(posedge PCLK) begin
        if (PSEL && !PENABLE && !PWRITE && (PADDR == ADDR_DR))
            rx_dr_latch <= rx_fifo_rdata;
    end
    assign rx_fifo_rd = apb_read && (word_addr == ADDR_DR);
    assign rx_fifo_wr = ((mode == 2'b00) && usart_rx_fifo_wr) ||
                        ((mode == 2'b01) && spi_rx_fifo_wr) ||
                        ((mode == 2'b10) && i2c_rx_fifo_wr);
    assign rx_fifo_wdata = (mode == 2'b00) ? usart_rx_fifo_wdata :
                           (mode == 2'b01) ? spi_rx_fifo_wdata :
                           i2c_rx_fifo_wdata;
    assign rx_fifo_flush = (apb_write && (word_addr == ADDR_FIFOCTRL) && PWDATA[8]) ||
                           sw_reset;

    //==========================================================================
    // Protocol Engine Instances
    //==========================================================================

    // USART Transmitter
    nc_sercom_usart_tx #(
        .FIFO_DEPTH(FIFO_DEPTH),
        .DATA_WIDTH(32)
    ) usart_tx_inst (
        .clk         (PCLK),
        .rst_n       (PRESETn && !sw_reset),
        .enable      (periph_en && (mode == 2'b00)),
        .tx_en       (tx_en),
        .clkdiv      (timing_reg[15:0]),
        .chsize      (chsize),
        .parity      (parity),
        .sbmode      (sbmode),
        .msbfirst    (msbfirst),
        .fifo_rd     (usart_tx_fifo_rd),
        .fifo_rdata  (tx_fifo_rdata),
        .fifo_empty  (tx_fifo_empty),
        .busy        (usart_tx_busy),
        .tx_done     (usart_tx_done),
        .tx_out      (usart_tx_out)
    );

    // USART Receiver
    nc_sercom_usart_rx #(
        .FIFO_DEPTH(FIFO_DEPTH),
        .DATA_WIDTH(32)
    ) usart_rx_inst (
        .clk         (PCLK),
        .rst_n       (PRESETn && !sw_reset),
        .enable      (periph_en && (mode == 2'b00)),
        .rx_en       (rx_en),
        .clkdiv      (timing_reg[15:0]),
        .chsize      (chsize),
        .parity      (parity),
        .msbfirst    (msbfirst),
        .sampr       (sampr),
        .fifo_wr     (usart_rx_fifo_wr),
        .fifo_wdata  (usart_rx_fifo_wdata),
        .fifo_full   (rx_fifo_full),
        .busy        (usart_rx_busy),
        .rx_ne       (usart_rx_ne),
        .rx_in       (loopback ? usart_tx_out : pad_in_i[0]),
        .frame_err   (usart_frame_err),
        .parity_err  (usart_parity_err),
        .break_det   (usart_break_det),
        .bufovf_pulse(usart_bufovf_pulse)
    );

    // SPI Engine
    nc_sercom_spi #(
        .FIFO_DEPTH(FIFO_DEPTH),
        .DATA_WIDTH(32)
    ) spi_inst (
        .clk         (PCLK),
        .rst_n       (PRESETn && !sw_reset),
        .enable      (periph_en && (mode == 2'b01)),
        .tx_en       (tx_en),
        .rx_en       (rx_en),
        .clkdiv      (timing_reg[15:0]),
        .cpol        (modecfg_reg[13]),
        .cpha        (modecfg_reg[12]),
        .msbfirst    (msbfirst),
        .framesize   (spi_cfg_reg[1:0]),
        .tx_fifo_rd  (spi_tx_fifo_rd),
        .tx_fifo_rdata(tx_fifo_rdata),
        .tx_fifo_empty(tx_fifo_empty),
        .rx_fifo_wr  (spi_rx_fifo_wr),
        .rx_fifo_wdata(spi_rx_fifo_wdata),
        .rx_fifo_full(rx_fifo_full),
        .cs_mask     (spi_cs_reg[3:0]),
        .cs_n_o      (spi_cs_n),
        .busy        (spi_busy),
        .tx_done     (spi_tx_done),
        .sck_out_o   (spi_sck_out),
        .sck_oe_o    (spi_sck_oe),
        .mosi_out_o  (spi_mosi_out),
        .mosi_oe_o   (spi_mosi_oe),
        .miso_in_i   (loopback ? spi_mosi_out : pad_in_i[1])
    );

    // I2C Engine
    nc_sercom_i2c #(
        .FIFO_DEPTH(FIFO_DEPTH),
        .DATA_WIDTH(32)
    ) i2c_inst (
        .clk         (PCLK),
        .rst_n       (PRESETn && !sw_reset),
        .enable      (periph_en && (mode == 2'b10)),
        .tx_en       (tx_en),
        .rx_en       (rx_en),
        .clkdiv      (timing_reg[15:0]),
        .slave_addr  (addr_reg[10:0]),
        // MODECFG[13:12] are RESERVED — they used to feed I2C `tenbit`
        // and `gcen` inputs, but the engine ignored them. The ports
        // have been removed (issue #9 item 6). The bits are left in the
        // register layout so existing software that writes them has no
        // visible side effect; a future RTL extension may reclaim them.
        .hsmd        (modecfg_reg[7:6] == 2'b10),
        .cmd         (i2c_cmd),
        .ackact      (i2c_ackact),
        .tx_fifo_rd  (i2c_tx_fifo_rd),
        .tx_fifo_rdata(tx_fifo_rdata),
        .tx_fifo_empty(tx_fifo_empty),
        .rx_fifo_wr  (i2c_rx_fifo_wr),
        .rx_fifo_wdata(i2c_rx_fifo_wdata),
        .rx_fifo_full(rx_fifo_full),
        .busy        (i2c_busy_engine),
        .tx_done     (i2c_tx_done),
        .bus_busy    (i2c_bus_busy_engine),
        .arb_lost    (i2c_arb_lost_engine),
        .rx_nack     (i2c_rx_nack_engine),
        .sda_out_o   (i2c_sda_out),
        .sda_oe_o    (i2c_sda_oe),
        .sda_in_i    (pad_in_i[0]),  // Default: pad0 = SDA
        .scl_out_o   (i2c_scl_out),
        .scl_oe_o    (i2c_scl_oe),
        .scl_in_i    (pad_in_i[1])   // Default: pad1 = SCL
    );

    //==========================================================================
    // Pad Multiplexing (split interface)
    //==========================================================================
    // Route protocol engine signals to pads based on mode.
    // Default pad assignments:
    //   USART: pad0=RX(in), pad1=TX(out)
    //   SPI:   pad0=MOSI(out), pad1=MISO(in), pad2=SCK(out), pad3=CS(out)
    //   I2C:   pad0=SDA(open-drain), pad1=SCL(open-drain)

    reg [5:0] pad_out_mux;
    reg [5:0] pad_oe_mux;

    always @(*) begin
        pad_out_mux = 6'b000000;
        pad_oe_mux  = 6'b000000;

        case (mode)
            2'b00: begin  // USART
                // pad0 = RX (input only, no drive)
                pad_out_mux[1] = usart_tx_out;
                pad_oe_mux[1]  = periph_en && tx_en;
            end
            2'b01: begin  // SPI
                // pad0 = MOSI
                pad_out_mux[0] = spi_mosi_out;
                pad_oe_mux[0]  = spi_mosi_oe;
                // pad1 = MISO (input only)
                // pad2 = SCK
                pad_out_mux[2] = spi_sck_out;
                pad_oe_mux[2]  = spi_sck_oe;
                // pad3 = CS_N[0]
                pad_out_mux[3] = spi_cs_n[0];
                pad_oe_mux[3]  = periph_en;
            end
            2'b10: begin  // I2C (open-drain)
                // pad0 = SDA
                pad_out_mux[0] = i2c_sda_out;
                pad_oe_mux[0]  = i2c_sda_oe;
                // pad1 = SCL
                pad_out_mux[1] = i2c_scl_out;
                pad_oe_mux[1]  = i2c_scl_oe;
            end
            default: begin
                pad_out_mux = 6'b000000;
                pad_oe_mux  = 6'b000000;
            end
        endcase
    end

    assign pad_out_o = pad_out_mux;
    assign pad_oe_o  = pad_oe_mux;

    //==========================================================================
    // Status Aggregation
    //==========================================================================
    always @* begin
        case (mode)
            2'b00: begin  // USART
                sr_busy = usart_tx_busy || usart_rx_busy;
                sr_idle = ~sr_busy;
                sr_tc   = usart_tx_done && tx_fifo_empty;
                sr_err  = usart_frame_err | usart_parity_err | usart_break_det;
            end
            2'b01: begin  // SPI
                sr_busy = spi_busy;
                sr_idle = ~sr_busy;
                sr_tc   = spi_tx_done && tx_fifo_empty;
                sr_err  = 1'b0;
            end
            2'b10: begin  // I2C
                sr_busy = i2c_busy_engine;
                sr_idle = ~sr_busy && ~i2c_bus_busy_engine;
                sr_tc   = i2c_tx_done && tx_fifo_empty;
                sr_err  = i2c_arb_lost_engine | i2c_rx_nack_engine;
            end
            default: begin
                sr_busy = 1'b0;
                sr_idle = 1'b1;
                sr_tc   = 1'b0;
                sr_err  = 1'b0;
            end
        endcase
    end

    //==========================================================================
    // Register Write Logic
    //==========================================================================
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            cr_reg        <= 32'h0000_0000;
            modecfg_reg   <= 32'h0000_0000;
            timing_reg    <= 32'h0000_0000;
            addr_reg      <= 32'h0000_0000;
            frame_reg     <= 32'h0000_0000;
            im_reg        <= 32'h0000_0000;
            dmacr_reg     <= 32'h0000_0000;
            fifoctrl_reg  <= 32'h0000_0000;
            i2c_cmd_reg   <= 32'h0000_0000;
            spi_cs_reg    <= 32'h0000_0000;
            spi_cfg_reg   <= 32'h0000_0000;
            usart_rxto_reg <= 32'h0000_0000;

            usart_perr   <= 1'b0;
            usart_ferr   <= 1'b0;
            usart_bufovf <= 1'b0;
            usart_brk    <= 1'b0;
            i2c_arblost  <= 1'b0;
            i2c_rxnack   <= 1'b0;
        end else begin
            // Software reset (self-clearing): CR[1]
            if (sw_reset) begin
                cr_reg[1] <= 1'b0;
            end

            if (apb_write) begin
                case (word_addr)
                    // CR: [0]=EN, [1]=SRST, [3:2]=MODE, [4]=LPMEN, [5]=DBGEN,
                    //     [8]=TXEN, [9]=RXEN
                    ADDR_CR: cr_reg <= {22'h0, PWDATA[9], PWDATA[8],
                                        2'b00, PWDATA[5], PWDATA[4],
                                        PWDATA[3:2], PWDATA[1], PWDATA[0]};

                    // Standard front-end
                    ADDR_IM:       im_reg       <= PWDATA;
                    ADDR_DMACR:    dmacr_reg    <= PWDATA;
                    ADDR_FIFOCTRL: fifoctrl_reg <= PWDATA;

                    // Extension space (0x100+)
                    ADDR_MODECFG:      modecfg_reg    <= PWDATA;
                    ADDR_TIMING:       timing_reg     <= PWDATA;
                    ADDR_ADDR:         addr_reg       <= PWDATA;
                    ADDR_FRAME:        frame_reg      <= PWDATA;
                    ADDR_I2C_CMD:      i2c_cmd_reg    <= PWDATA;
                    ADDR_SPI_CS:       spi_cs_reg     <= PWDATA;
                    ADDR_SPI_CFG:      spi_cfg_reg    <= PWDATA;
                    ADDR_USART_RXTO:   usart_rxto_reg <= PWDATA;
                    default: ;
                endcase

                // ICR W1C handling for RIS flops lives in the dedicated
                // RIS-flag block below — keeping it in one place keeps
                // each flop single-driven, which Yosys requires (multi-
                // driven flops were silently resolved to constant 0
                // before this refactor).

                // USART_STATUS: Write-1-to-clear for sticky bits
                if (word_addr == ADDR_USART_STATUS) begin
                    if (PWDATA[2])  usart_perr   <= 1'b0;
                    if (PWDATA[3])  usart_ferr   <= 1'b0;
                    if (PWDATA[5])  usart_bufovf <= 1'b0;
                    if (PWDATA[6])  usart_brk    <= 1'b0;
                end
            end

            // Capture error flags — PERR and FERR latch sticky on the
            // 1-cycle pulse from the RX engine and are cleared via W1C
            // on USART_STATUS[2] / [3] above (issue #9 item 1).
            if (usart_parity_err) usart_perr <= 1'b1;
            if (usart_frame_err)  usart_ferr <= 1'b1;
            // bufovf: RX engine pulses bufovf_pulse when a byte completes
            // but the FIFO is full (sticky until W1C via USART_STATUS[5]).
            if (usart_bufovf_pulse)
                usart_bufovf <= 1'b1;
            if (usart_break_det)
                usart_brk <= 1'b1;
            i2c_arblost <= i2c_arb_lost_engine;
            i2c_rxnack  <= i2c_rx_nack_engine;
        end
    end

    //==========================================================================
    // Status Register Assembly
    //==========================================================================
    // SR bit layout (CSR compliant): TXE[0], RXNE[1], BUSY[2], ERR[3], IDLE[4], TC[5]
    wire [31:0] sr_value = {26'h0, sr_tc, sr_idle, sr_err, sr_busy, sr_rxne, sr_txe};

    // RIS/MIS bit layout: TX[0], RX[1], (reserved[2]), IDLE[3], ERR[4], RXTO[5], TC[6]
    wire [31:0] ris_value = {25'h0, tc_ris_q, 1'b0, err_ris_q, idle_ris_q, 1'b0, rx_ris_q, tx_ris_q};
    wire [31:0] mis_value = {25'h0, tc_mis, 1'b0, err_mis, idle_mis, 1'b0, rx_mis, tx_mis};

    assign PRDATA = apb_read ? (
        // Standard front-end (0x000-0x0FF)
        (word_addr == ADDR_CR)        ? cr_reg :
        (word_addr == ADDR_SR)        ? sr_value :
        (word_addr == ADDR_DR)        ? rx_dr_latch :
        (word_addr == ADDR_IM)        ? im_reg :
        (word_addr == ADDR_RIS)       ? ris_value :
        (word_addr == ADDR_MIS)       ? mis_value :
        (word_addr == ADDR_DMACR)     ? dmacr_reg :
        (word_addr == ADDR_TXLVL)     ? {27'h0, tx_lvl} :
        (word_addr == ADDR_RXLVL)     ? {27'h0, rx_lvl} :
        (word_addr == ADDR_FIFOCTRL)  ? fifoctrl_reg :
        (word_addr == ADDR_FIFOSTR)   ? {17'h0, rx_lvl, 5'h0, tx_lvl} :
        // Extension space (0x100+)
        (word_addr == ADDR_MODECFG)      ? modecfg_reg :
        (word_addr == ADDR_TIMING)       ? timing_reg :
        (word_addr == ADDR_ADDR)         ? addr_reg :
        (word_addr == ADDR_FRAME)        ? frame_reg :
        (word_addr == ADDR_I2C_STATUS)   ? {29'h0, i2c_rxnack, i2c_arblost, i2c_busy_engine} :
        (word_addr == ADDR_SPI_CS)       ? spi_cs_reg :
        (word_addr == ADDR_SPI_CFG)      ? spi_cfg_reg :
        (word_addr == ADDR_USART_STATUS) ? {25'h0, usart_brk, usart_bufovf, usart_coll, usart_ferr, usart_perr, 1'b0, usart_tx_busy} :
        (word_addr == ADDR_USART_RXTO)   ? usart_rxto_reg :
        // Discovery
        (word_addr == ADDR_FEATURE)   ? FEATURE_VALUE :
        (word_addr == ADDR_ID)        ? ID_VALUE :
        32'h0000_0000
    ) : 32'h0000_0000;

    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    //==========================================================================
    // Interrupt Flag Generation
    //==========================================================================
    // Every RIS flop is driven from EXACTLY this one always block. The
    // prior implementation split reset/event-set into this block and
    // ICR-clear into the register-write block; iverilog tolerated the
    // resulting double-driver via last-write-wins, but Yosys 0.57
    // correctly flagged "Driver-driver conflict ... Resolved using
    // constant" and silently dropped the flop driver, leaving all five
    // RIS bits tied to 0 in the synthesized netlist. Keep this block
    // single-source-of-truth for each RIS flop.
    //
    // ICR bit map (per nc_sercom.reg.yaml):
    //   bit 1: RXIC   -> clears rx_ris_q  for one cycle
    //   bit 3: IDLEIC -> clears idle_ris_q for one cycle
    //   bit 4: ERRIC  -> clears err_ris_q (sticky)
    //   bit 6: TCIC   -> clears tc_ris_q  (sticky)
    //   bit 0 (tx_ris_q) is deliberately NOT in ICR — tx is pure level.
    wire icr_write = apb_write && (word_addr == ADDR_ICR);
    wire icr_clr_rx   = icr_write && PWDATA[1];
    wire icr_clr_idle = icr_write && PWDATA[3];
    wire icr_clr_err  = icr_write && PWDATA[4];
    wire icr_clr_tc   = icr_write && PWDATA[6];

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            tx_ris_q   <= 1'b0;
            rx_ris_q   <= 1'b0;
            idle_ris_q <= 1'b0;
            err_ris_q  <= 1'b0;
            tc_ris_q   <= 1'b0;
        end else begin
            // Level-sensitive bits track the source continuously. An ICR
            // write that targets them forces 0 for this cycle; next cycle
            // they re-sample the source and may re-assert if it's still
            // high. Existing test_irq_level_sensitive / test_idle_irq
            // depend on the re-assert behavior.
            tx_ris_q   <= tx_fifo_empty;
            rx_ris_q   <= icr_clr_rx   ? 1'b0 : ~rx_fifo_empty;
            idle_ris_q <= icr_clr_idle ? 1'b0 : (sr_idle && ~sr_busy);

            // Event/sticky bits: ICR W1C wins over event-set when both
            // happen on the same cycle (per spec). Otherwise sticky-set
            // on the 1-cycle pulse from the protocol engines and hold.
            // Without this latching, software could never catch a
            // 1-cycle event (same bug pattern as USART PERR/FERR in
            // commit 0cbf9d3).
            if (icr_clr_err)
                err_ris_q <= 1'b0;
            else if (sr_err)
                err_ris_q <= 1'b1;

            if (icr_clr_tc)
                tc_ris_q <= 1'b0;
            else if (sr_tc)
                tc_ris_q <= 1'b1;
        end
    end

`ifdef VERILATOR
    //==========================================================================
    // SystemVerilog Assertions (Verilator-only)
    //==========================================================================
    // Guarded with `ifdef VERILATOR so iverilog 12 (no SVA support) still
    // compiles the file. These are continuous protocol-invariant monitors;
    // they fire automatically during any verify-coverage run and contribute
    // `cover property' hits to the coverage report.

    // APB3 handshake: once PSEL && PENABLE asserts, the slave (we always
    // hold PREADY high) must keep the access valid; PADDR/PWDATA cannot
    // change mid-cycle. (PREADY is tied high here, so the timed form is
    // trivially satisfied — but the cover demonstrates real APB accesses
    // happen, which is information.)
    apb_handshake_cover: cover property (
        @(posedge PCLK) disable iff (!PRESETn)
        PSEL && PENABLE |-> PREADY);

    // SPI: when state is not IDLE, the CS output must have at most ONE
    // line low (one-hot active select). Catches CS-mux regressions.
    spi_cs_one_hot: assert property (
        @(posedge PCLK) disable iff (!PRESETn)
        ((mode == 2'b01) && (spi_inst.state != 2'd0))
            |-> $onehot0(~spi_inst.cs_n_o));

    // I2C: master must never assert START while bus_busy is true.
    // Protects against double-START races.
    i2c_start_only_when_idle: assert property (
        @(posedge PCLK) disable iff (!PRESETn)
        (i2c_inst.state == 4'd1)   // STATE_START
            |-> $past(!i2c_inst.bus_busy));

    // Coverage points (non-fatal — cover that we did exercise these):
    sr_tc_pulse_cover: cover property (
        @(posedge PCLK) disable iff (!PRESETn) sr_tc);
    sr_err_pulse_cover: cover property (
        @(posedge PCLK) disable iff (!PRESETn) sr_err);
`endif

endmodule

`default_nettype wire
