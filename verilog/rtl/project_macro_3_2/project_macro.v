// SPDX-License-Identifier: Apache-2.0
// project_macro — USB CDC + FLL + RC Oscillators + nc_sercom test chip
//
// GPIO Pin Map (bottom edge, 15 pins → Caravel right pads):
//   [0]  : uart_rx      (input)
//   [1]  : uart_tx      (output)
//   [2]  : xclk         (input, external clock 12 MHz)
//   [3]  : usb_dp       (bidirectional)
//   [4]  : usb_dm       (bidirectional)
//   [5]  : usb_pu       (output, pullup enable — needs ext 1.5kΩ to D+)
//   [6]  : fll_mon      (output, FLL output ÷ N)
//   [7]  : rc16m_mon    (output, 16M RC OSC ÷ M)
//   [8]  : rc500k_mon   (output, 500k RC OSC ÷ K)
//   [9]  : usb_cfg      (output, USB configured status)
//   [10] : clk48m_mon   (output, 48 MHz FLL/2 clock, gated)
//   [11] : ext_rst_n    (input, active-low external reset)
//   [12] : adpor_mon    (output, all-digital PoR pulse — monitoring only)
//   [13-14]: spare
//
// Right-edge (9 pins): nc_sercom pads + spares
//   [0-1] : spare
//   [2-7] : sercom_pad[0:5]  (USART/SPI/I2C, runtime-configurable direction)
//   [8]   : spare
//
// Top-edge (14 pins): all spare (AttoIO removed)
//   [0-13]: spare
//
// Clock architecture:
//   xclk (12 MHz GPIO) -> fracn_dll -> 96 MHz -> /2 -> 48 MHz USB clock (clk_i)
//   app_clk_i = xclk (same as APB domain; USB IP handles clk_i <-> app_clk_i CDC)
//   FLL bypass mode: xclk directly to USB clk_i (for debug)
//   RC OSC 16 MHz: monitor output + optional FLL reference
//   RC OSC 500 kHz: low-frequency monitor output
//
// APB address map (via UART APB master, 8 KB slots):
//   0x0000: Clock control (FLL, RC OSC enables, dividers, muxes, USB pad)
//   0x2000: Status registers (freq counters, sync'd status, IRQ status @ 0x2010)
//   0x4000: USB CDC FIFO (read/write bytes)
//   0x6000: unused (was AttoIO; tied off with PSLVERR=0, PREADY=1)
//   0x8000: nc_sercom (USART/SPI/I2C, 12-bit internal address space)

`timescale 1ns / 1ps
`default_nettype none

module project_macro #(
    parameter XCLK_FREQ_MHZ    = 12,
    parameter BAUD_DIV         = 16'd13
)(
`ifdef USE_POWER_PINS
    inout  vccd1,
    inout  vssd1,
`endif
    input  wire        clk,
    input  wire        reset_n,
    input  wire        por_n,

    input  wire [14:0] gpio_bot_in,
    output wire [14:0] gpio_bot_out,
    output wire [14:0] gpio_bot_oeb,
    output wire [44:0] gpio_bot_dm,

    input  wire [8:0]  gpio_rt_in,
    output wire [8:0]  gpio_rt_out,
    output wire [8:0]  gpio_rt_oeb,
    output wire [26:0] gpio_rt_dm,

    input  wire [13:0] gpio_top_in,
    output wire [13:0] gpio_top_out,
    output wire [13:0] gpio_top_oeb,
    output wire [41:0] gpio_top_dm
);

    wire sys_rst_n = reset_n & por_n;

    wire ext_rst_raw = gpio_bot_in[11];
    reg  ext_rst_meta, ext_rst_sync;
    always @(posedge xclk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            ext_rst_meta <= 1'b1;
            ext_rst_sync <= 1'b1;
        end else begin
            ext_rst_meta <= ext_rst_raw;
            ext_rst_sync <= ext_rst_meta;
        end
    end

    wire rst_n = sys_rst_n & ext_rst_sync;

    // All-digital PoR (characterization only — routed to gpio_bot[12]).
    // Self-contained, no inputs; output is the PoR pulse.
    wire adpor_por_n;
    por_macro u_adpor_macro (
        .por_n_out (adpor_por_n)
    );

    wire uart_rx_in = gpio_bot_in[0];
    wire xclk       = gpio_bot_in[2];

    wire        fll_en;
    wire        rc16m_en;
    wire        rc500k_en;
    wire [2:0]  sel_mon;
    wire        fll_bypass;
    wire        usb_rst_n;
    wire [7:0]  fll_div;
    wire        fll_dco;
    wire [25:0] fll_ext_trim;
    wire [15:0] fll_mon_div;
    wire [15:0] rc16m_mon_div;
    wire [15:0] rc500k_mon_div;
    wire [15:0] clk_mon_div;
    wire        fll_mon_en;
    wire        rc16m_mon_en;
    wire        rc500k_mon_en;
    wire        clk_mon_en;
    wire        clk48m_mon_en;
    wire [2:0]  usb_dp_dm;
    wire [2:0]  usb_dn_dm;
    wire [2:0]  usb_pu_dm;

    wire rc16m_clk;
    sky130_ef_ip__rc_osc_16M u_rc_osc_16M (
        .ena  (rc16m_en),
        .dout (rc16m_clk)
    );

    wire rc500k_clk;
    sky130_ef_ip__rc_osc_500k u_rc_osc_500k (
        .ena  (rc500k_en),
        .dout (rc500k_clk)
    );

    wire fll_clk_96m, fll_clk_48m;
    fll_top u_fll_top (
        .resetb   (rst_n),
        .enable   (fll_en),
        .osc_ref  (xclk),
        .div      (fll_div),
        .dco      (fll_dco),
        .ext_trim (fll_ext_trim),
        .clk_96m  (fll_clk_96m),
        .clk_48m  (fll_clk_48m)
    );

    wire usb_clk;
    clk_mux_2to1 u_usb_clk_mux (
        .clk0    (fll_clk_48m),
        .clk1    (xclk),
        .sel     (fll_bypass),
        .rst_n   (rst_n),
        .clk_out (usb_clk)
    );

    localparam NUM_MON_SOURCES = 6;
    wire [NUM_MON_SOURCES-1:0] mon_sources;
    assign mon_sources[0] = clk;
    assign mon_sources[1] = xclk;
    assign mon_sources[2] = fll_clk_96m;
    assign mon_sources[3] = fll_clk_48m;
    assign mon_sources[4] = rc16m_clk;
    assign mon_sources[5] = rc500k_clk;

    wire mon_mid_a, mon_mid_b, mon_mid_c, mon_mid_d, mon_clk;

    clk_mux_2to1 u_mon_mux0 (
        .clk0(mon_sources[0]), .clk1(mon_sources[1]),
        .sel(sel_mon[0]), .rst_n(rst_n), .clk_out(mon_mid_a)
    );
    clk_mux_2to1 u_mon_mux1 (
        .clk0(mon_sources[2]), .clk1(mon_sources[3]),
        .sel(sel_mon[0]), .rst_n(rst_n), .clk_out(mon_mid_b)
    );
    clk_mux_2to1 u_mon_mux2 (
        .clk0(mon_sources[4]), .clk1(mon_sources[5]),
        .sel(sel_mon[0]), .rst_n(rst_n), .clk_out(mon_mid_c)
    );
    clk_mux_2to1 u_mon_mux3 (
        .clk0(mon_mid_a), .clk1(mon_mid_b),
        .sel(sel_mon[1]), .rst_n(rst_n), .clk_out(mon_mid_d)
    );
    clk_mux_2to1 u_mon_mux4 (
        .clk0(mon_mid_d), .clk1(mon_mid_c),
        .sel(sel_mon[2]), .rst_n(rst_n), .clk_out(mon_clk)
    );

    wire fll_mon_clk, rc16m_mon_clk, rc500k_mon_clk, clk_mon_clk;

    clk_div #(.WIDTH(16)) u_fll_mon_div (
        .clk_in(fll_clk_96m), .rst_n(rst_n),
        .en(fll_mon_en), .div_ratio(fll_mon_div), .clk_out(fll_mon_clk)
    );
    clk_div #(.WIDTH(16)) u_rc16m_mon_div (
        .clk_in(rc16m_clk), .rst_n(rst_n),
        .en(rc16m_mon_en), .div_ratio(rc16m_mon_div), .clk_out(rc16m_mon_clk)
    );
    clk_div #(.WIDTH(16)) u_rc500k_mon_div (
        .clk_in(rc500k_clk), .rst_n(rst_n),
        .en(rc500k_mon_en), .div_ratio(rc500k_mon_div), .clk_out(rc500k_mon_clk)
    );
    clk_div #(.WIDTH(16)) u_clk_mon_div (
        .clk_in(mon_clk), .rst_n(rst_n),
        .en(clk_mon_en), .div_ratio(clk_mon_div), .clk_out(clk_mon_clk)
    );

    wire uart_tx_out;
    wire uart_locked;

    wire        S0_PSEL,  S1_PSEL,  S2_PSEL,  S3_PSEL;
    wire        S4_PSEL,  S5_PSEL,  S6_PSEL,  S7_PSEL;
    wire [12:0] S0_PADDR, S1_PADDR, S2_PADDR, S3_PADDR;
    wire [12:0] S4_PADDR, S5_PADDR, S6_PADDR, S7_PADDR;
    wire        S0_PENABLE, S1_PENABLE, S2_PENABLE, S3_PENABLE;
    wire        S4_PENABLE, S5_PENABLE, S6_PENABLE, S7_PENABLE;
    wire        S0_PWRITE,  S1_PWRITE,  S2_PWRITE,  S3_PWRITE;
    wire        S4_PWRITE,  S5_PWRITE,  S6_PWRITE,  S7_PWRITE;
    wire [31:0] S0_PWDATA,  S1_PWDATA,  S2_PWDATA,  S3_PWDATA;
    wire [31:0] S4_PWDATA,  S5_PWDATA,  S6_PWDATA,  S7_PWDATA;
    wire [31:0] S0_PRDATA,  S1_PRDATA,  S2_PRDATA,  S3_PRDATA;
    wire [31:0] S4_PRDATA,  S5_PRDATA,  S6_PRDATA,  S7_PRDATA;
    wire        S0_PREADY,  S1_PREADY,  S2_PREADY,  S3_PREADY;
    wire        S4_PREADY,  S5_PREADY,  S6_PREADY,  S7_PREADY;
    wire        S0_PSLVERR, S1_PSLVERR, S2_PSLVERR, S3_PSLVERR;
    wire        S4_PSLVERR, S5_PSLVERR, S6_PSLVERR, S7_PSLVERR;

    // Slot 4 (0x8000) is driven by nc_sercom; tie off the remaining
    // slots. Slot 3 (0x6000) was AttoIO and is now reserved.
    assign S3_PRDATA = 32'd0;  assign S5_PRDATA = 32'd0;
    assign S6_PRDATA = 32'd0;  assign S7_PRDATA = 32'd0;
    assign S3_PREADY = 1'b1;   assign S5_PREADY = 1'b1;
    assign S6_PREADY = 1'b1;   assign S7_PREADY = 1'b1;
    assign S3_PSLVERR = 1'b0;  assign S5_PSLVERR = 1'b0;
    assign S6_PSLVERR = 1'b0;  assign S7_PSLVERR = 1'b0;

    uart_apb_sys #(
        .DEFAULT_DIVISOR (BAUD_DIV),
        .NUM_SLAVES      (8),
        .SLOT_BITS       (13)
    ) u_uart_apb_sys (
        .clk        (xclk),
        .rst_n      (rst_n),
        .uart_rx    (uart_rx_in),
        .uart_tx    (uart_tx_out),
        .locked     (uart_locked),
        .S0_PSEL    (S0_PSEL),    .S0_PADDR    (S0_PADDR),
        .S0_PENABLE (S0_PENABLE), .S0_PWRITE   (S0_PWRITE),
        .S0_PWDATA  (S0_PWDATA),  .S0_PRDATA   (S0_PRDATA),
        .S0_PREADY  (S0_PREADY),  .S0_PSLVERR  (S0_PSLVERR),
        .S1_PSEL    (S1_PSEL),    .S1_PADDR    (S1_PADDR),
        .S1_PENABLE (S1_PENABLE), .S1_PWRITE   (S1_PWRITE),
        .S1_PWDATA  (S1_PWDATA),  .S1_PRDATA   (S1_PRDATA),
        .S1_PREADY  (S1_PREADY),  .S1_PSLVERR  (S1_PSLVERR),
        .S2_PSEL    (S2_PSEL),    .S2_PADDR    (S2_PADDR),
        .S2_PENABLE (S2_PENABLE), .S2_PWRITE   (S2_PWRITE),
        .S2_PWDATA  (S2_PWDATA),  .S2_PRDATA   (S2_PRDATA),
        .S2_PREADY  (S2_PREADY),  .S2_PSLVERR  (S2_PSLVERR),
        .S3_PSEL    (S3_PSEL),    .S3_PADDR    (S3_PADDR),
        .S3_PENABLE (S3_PENABLE), .S3_PWRITE   (S3_PWRITE),
        .S3_PWDATA  (S3_PWDATA),  .S3_PRDATA   (S3_PRDATA),
        .S3_PREADY  (S3_PREADY),  .S3_PSLVERR  (S3_PSLVERR),
        .S4_PSEL    (S4_PSEL),    .S4_PADDR    (S4_PADDR),
        .S4_PENABLE (S4_PENABLE), .S4_PWRITE   (S4_PWRITE),
        .S4_PWDATA  (S4_PWDATA),  .S4_PRDATA   (S4_PRDATA),
        .S4_PREADY  (S4_PREADY),  .S4_PSLVERR  (S4_PSLVERR),
        .S5_PSEL    (S5_PSEL),    .S5_PADDR    (S5_PADDR),
        .S5_PENABLE (S5_PENABLE), .S5_PWRITE   (S5_PWRITE),
        .S5_PWDATA  (S5_PWDATA),  .S5_PRDATA   (S5_PRDATA),
        .S5_PREADY  (S5_PREADY),  .S5_PSLVERR  (S5_PSLVERR),
        .S6_PSEL    (S6_PSEL),    .S6_PADDR    (S6_PADDR),
        .S6_PENABLE (S6_PENABLE), .S6_PWRITE   (S6_PWRITE),
        .S6_PWDATA  (S6_PWDATA),  .S6_PRDATA   (S6_PRDATA),
        .S6_PREADY  (S6_PREADY),  .S6_PSLVERR  (S6_PSLVERR),
        .S7_PSEL    (S7_PSEL),    .S7_PADDR    (S7_PADDR),
        .S7_PENABLE (S7_PENABLE), .S7_PWRITE   (S7_PWRITE),
        .S7_PWDATA  (S7_PWDATA),  .S7_PRDATA   (S7_PRDATA),
        .S7_PREADY  (S7_PREADY),  .S7_PSLVERR  (S7_PSLVERR)
    );

    apb_clk_ctrl u_apb_clk_ctrl (
        .clk           (xclk),
        .rst_n         (rst_n),
        .PADDR         (S0_PADDR),  .PSEL     (S0_PSEL),
        .PENABLE       (S0_PENABLE), .PWRITE  (S0_PWRITE),
        .PWDATA        (S0_PWDATA),  .PRDATA  (S0_PRDATA),
        .PREADY        (S0_PREADY),  .PSLVERR (S0_PSLVERR),
        .fll_en        (fll_en),
        .rc16m_en      (rc16m_en),
        .rc500k_en     (rc500k_en),
        .sel_mon       (sel_mon),
        .fll_bypass    (fll_bypass),
        .usb_rst_n     (usb_rst_n),
        .fll_div       (fll_div),
        .fll_dco       (fll_dco),
        .fll_ext_trim  (fll_ext_trim),
        .fll_mon_div   (fll_mon_div),
        .rc16m_mon_div (rc16m_mon_div),
        .rc500k_mon_div(rc500k_mon_div),
        .clk_mon_div   (clk_mon_div),
        .fll_mon_en    (fll_mon_en),
        .rc16m_mon_en  (rc16m_mon_en),
        .rc500k_mon_en (rc500k_mon_en),
        .clk_mon_en    (clk_mon_en),
        .clk48m_mon_en (clk48m_mon_en),
        .usb_dp_dm     (usb_dp_dm),
        .usb_dn_dm     (usb_dn_dm),
        .usb_pu_dm     (usb_pu_dm)
    );

    apb_status u_apb_status (
        .clk           (xclk),
        .rst_n         (rst_n),
        .PADDR         (S1_PADDR),  .PSEL     (S1_PSEL),
        .PENABLE       (S1_PENABLE), .PWRITE  (S1_PWRITE),
        .PWDATA        (S1_PWDATA),  .PRDATA  (S1_PRDATA),
        .PREADY        (S1_PREADY),  .PSLVERR (S1_PSLVERR),
        .fll_clk96m_in (fll_clk_96m),
        .fll_clk48m_in (fll_clk_48m),
        .rc16m_clk_in  (rc16m_clk),
        .rc500k_clk_in (rc500k_clk),
        .fll_en_sts    (fll_en),
        .rc16m_en_sts  (rc16m_en),
        .rc500k_en_sts (rc500k_en),
        .sel_mon_sts   (sel_mon),
        .fll_bypass_sts(fll_bypass),
        .irq_attoio_in (1'b0),     // AttoIO removed from this revision
        .irq_sercom_in (sercom_irq)
    );

    wire [7:0] fifo_in_data;
    wire       fifo_in_valid;
    wire       fifo_in_ready;
    wire [7:0] fifo_out_data;
    wire       fifo_out_valid;
    wire       fifo_out_ready;

    apb_usb_fifo u_apb_usb_fifo (
        .clk           (xclk),
        .rst_n         (rst_n),
        .PADDR         (S2_PADDR),  .PSEL     (S2_PSEL),
        .PENABLE       (S2_PENABLE), .PWRITE  (S2_PWRITE),
        .PWDATA        (S2_PWDATA),  .PRDATA  (S2_PRDATA),
        .PREADY        (S2_PREADY),  .PSLVERR (S2_PSLVERR),
        .usb_in_data   (fifo_in_data),
        .usb_in_valid  (fifo_in_valid),
        .usb_in_ready  (fifo_in_ready),
        .usb_out_data  (fifo_out_data),
        .usb_out_valid (fifo_out_valid),
        .usb_out_ready (fifo_out_ready)
    );

    wire dp_pu, tx_en, dp_tx, dn_tx;
    wire usb_configured;

    usb_cdc #(
        .CHANNELS              (1),
        .BIT_SAMPLES           (4),
        .USE_APP_CLK           (1),
        .APP_CLK_FREQ          (12),
        .IN_BULK_MAXPACKETSIZE (8),
        .OUT_BULK_MAXPACKETSIZE(8)
    ) u_usb_cdc (
        .clk_i         (usb_clk),
        .rstn_i        (rst_n & usb_rst_n),
        .app_clk_i     (xclk),
        .out_data_o    (fifo_out_data),
        .out_valid_o   (fifo_out_valid),
        .out_ready_i   (fifo_out_ready),
        .in_data_i     (fifo_in_data),
        .in_valid_i    (fifo_in_valid),
        .in_ready_o    (fifo_in_ready),
        .frame_o       (),
        .configured_o  (usb_configured),
        .dp_pu_o       (dp_pu),
        .tx_en_o       (tx_en),
        .dp_tx_o       (dp_tx),
        .dn_tx_o       (dn_tx),
        .dp_rx_i       (gpio_bot_in[3]),
        .dn_rx_i       (gpio_bot_in[4])
    );

    // ----------------------------------------------------------------------
    // nc_sercom — multi-protocol serial peripheral (USART/SPI/I2C).
    // APB slot 4 (0x8000). 6 pads on the right edge gpio_rt[7:2].
    // irq_o is exposed via the chip-level IRQ status register at 0x2010;
    // DMA requests are not consumed in this design.
    // Vendored from github.com/nativechips/nc_lib (Apache-2.0); see
    // nc_sercom/UPSTREAM for provenance.
    // ----------------------------------------------------------------------
    wire [5:0] sercom_pad_out;
    wire [5:0] sercom_pad_oe;
    wire [5:0] sercom_pad_in;
    wire       sercom_irq;

    nc_sercom #(
        .FIFO_DEPTH (16)
    ) u_nc_sercom (
        .PCLK         (xclk),
        .PRESETn      (rst_n),
        .PADDR        (S4_PADDR[11:0]),
        .PSEL         (S4_PSEL),
        .PENABLE      (S4_PENABLE),
        .PWRITE       (S4_PWRITE),
        .PWDATA       (S4_PWDATA),
        .PRDATA       (S4_PRDATA),
        .PREADY       (S4_PREADY),
        .PSLVERR      (S4_PSLVERR),

        .irq_o        (sercom_irq),
        .dma_tx_req_o (/* unconnected */),
        .dma_rx_req_o (/* unconnected */),

        .pad_out_o    (sercom_pad_out),
        .pad_oe_o     (sercom_pad_oe),
        .pad_in_i     (sercom_pad_in)
    );

    assign sercom_pad_in = gpio_rt_in[7:2];

    assign gpio_bot_out[0]  = 1'b0;
    assign gpio_bot_out[1]  = uart_tx_out;
    assign gpio_bot_out[2]  = 1'b0;
    assign gpio_bot_out[3]  = dp_tx;
    assign gpio_bot_out[4]  = dn_tx;
    assign gpio_bot_out[5]  = 1'b1;
    assign gpio_bot_out[6]  = fll_mon_clk;
    assign gpio_bot_out[7]  = rc16m_mon_clk;
    assign gpio_bot_out[8]  = rc500k_mon_clk;
    assign gpio_bot_out[9]  = usb_configured;
    assign gpio_bot_out[10] = fll_clk_48m;
    assign gpio_bot_out[11] = 1'b0;
    assign gpio_bot_out[12] = adpor_por_n;
    assign gpio_bot_out[13] = 1'b0;
    assign gpio_bot_out[14] = 1'b0;

    assign gpio_bot_oeb[0]  = 1'b1;
    assign gpio_bot_oeb[1]  = 1'b0;
    assign gpio_bot_oeb[2]  = 1'b1;
    assign gpio_bot_oeb[3]  = ~tx_en;
    assign gpio_bot_oeb[4]  = ~tx_en;
    assign gpio_bot_oeb[5]  = ~dp_pu;
    assign gpio_bot_oeb[6]  = ~fll_mon_en;
    assign gpio_bot_oeb[7]  = ~rc16m_mon_en;
    assign gpio_bot_oeb[8]  = ~rc500k_mon_en;
    assign gpio_bot_oeb[9]  = 1'b0;
    assign gpio_bot_oeb[10] = ~clk48m_mon_en;
    assign gpio_bot_oeb[11] = 1'b1;        // ext_rst_n input
    assign gpio_bot_oeb[12] = 1'b0;        // adpor_por_n output
    assign gpio_bot_oeb[13] = 1'b1;        // spare
    assign gpio_bot_oeb[14] = 1'b1;        // spare

    assign gpio_bot_dm[0*3 +: 3] = 3'b001;
    assign gpio_bot_dm[1*3 +: 3] = 3'b110;
    assign gpio_bot_dm[2*3 +: 3] = 3'b001;
    assign gpio_bot_dm[3*3 +: 3] = usb_dp_dm;
    assign gpio_bot_dm[4*3 +: 3] = usb_dn_dm;
    assign gpio_bot_dm[5*3 +: 3] = usb_pu_dm;
    assign gpio_bot_dm[6*3 +: 3] = 3'b110;
    assign gpio_bot_dm[7*3 +: 3] = 3'b110;
    assign gpio_bot_dm[8*3 +: 3] = 3'b110;
    assign gpio_bot_dm[9*3 +: 3] = 3'b110;
    assign gpio_bot_dm[10*3 +: 3] = 3'b110;
    assign gpio_bot_dm[11*3 +: 3] = 3'b110;
    assign gpio_bot_dm[12*3 +: 3] = 3'b110;
    assign gpio_bot_dm[13*3 +: 3] = 3'b110;
    assign gpio_bot_dm[14*3 +: 3] = 3'b110;

    // Right edge: gpio_rt[7:2] are nc_sercom pads (bidirectional via pad_oe).
    // sercom uses active-high oe; project pad oeb is active-low -> invert.
    assign gpio_rt_out[7:2] = sercom_pad_out;
    assign gpio_rt_oeb[7:2] = ~sercom_pad_oe;
    // gpio_rt[8] is the only remaining spare pin.
    assign gpio_rt_out[8]   = 1'b0;
    assign gpio_rt_oeb[8]   = 1'b1;

    assign gpio_rt_dm[2*3 +: 3] = 3'b110;
    assign gpio_rt_dm[3*3 +: 3] = 3'b110;
    assign gpio_rt_dm[4*3 +: 3] = 3'b110;
    assign gpio_rt_dm[5*3 +: 3] = 3'b110;
    assign gpio_rt_dm[6*3 +: 3] = 3'b110;
    assign gpio_rt_dm[7*3 +: 3] = 3'b110;
    assign gpio_rt_dm[8*3 +: 3] = 3'b110;

    // gpio_rt[1:0] are now spare (AttoIO reduced to single-side, 14 GPIO on top).
    assign gpio_rt_out[1:0]     = 2'b0;
    assign gpio_rt_oeb[1:0]     = 2'b11;     // tri-state (input)
    assign gpio_rt_dm[0*3 +: 3] = 3'b110;
    assign gpio_rt_dm[1*3 +: 3] = 3'b110;

    // Top-edge pads are all spare (AttoIO removed). Tie outputs low,
    // oeb high (tri-state input), drive-mode neutral 3'b110.
    assign gpio_top_out = 14'b0;
    assign gpio_top_oeb = {14{1'b1}};
    genvar i;
    generate
        for (i = 0; i < 14; i = i + 1) begin : gen_top_dm
            assign gpio_top_dm[i*3 +: 3] = 3'b110;
        end
    endgenerate

endmodule
