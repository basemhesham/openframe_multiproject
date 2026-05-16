// SPDX-License-Identifier: Apache-2.0
// apb_usb_fifo — APB slave bridge to USB CDC FIFO interface
//
// Register map:
//   0x00 : DATA — write → USB IN FIFO,  read ← USB OUT FIFO
//   0x04 : STATUS
//          [0] tx_ready  (usb_in_ready)
//          [1] rx_valid   (usb_out_valid)
//
// Writes stall (PREADY=0) while a previous byte is still pending.
// Reads stall (PREADY=0) while no data is available from USB host.

`timescale 1ns / 1ps
`default_nettype none

module apb_usb_fifo (
    input  wire         clk,
    input  wire         rst_n,
    input  wire  [12:0] PADDR,
    input  wire         PSEL,
    input  wire         PENABLE,
    input  wire         PWRITE,
    input  wire  [31:0] PWDATA,
    output wire  [31:0] PRDATA,
    output wire         PREADY,
    output wire         PSLVERR,

    output wire  [7:0]  usb_in_data,
    output wire         usb_in_valid,
    input  wire         usb_in_ready,
    input  wire  [7:0]  usb_out_data,
    input  wire         usb_out_valid,
    output wire         usb_out_ready
);

    assign PSLVERR = 1'b0;

    wire apb_access = PSEL & PENABLE;
    wire apb_wr     = apb_access & PWRITE;
    wire apb_rd     = apb_access & ~PWRITE;
    wire sel_data   = (PADDR == 13'h00);
    wire sel_status = (PADDR == 13'h04);

    // ---- TX path: APB write → USB IN FIFO ----
    reg [7:0] tx_hold;
    reg       tx_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_hold    <= 8'd0;
            tx_pending <= 1'b0;
        end else begin
            if (tx_pending & usb_in_ready)
                tx_pending <= 1'b0;
            if (apb_wr & sel_data & ~tx_pending) begin
                tx_hold    <= PWDATA[7:0];
                tx_pending <= 1'b1;
            end
        end
    end

    assign usb_in_data  = tx_hold;
    assign usb_in_valid = tx_pending;

    // ---- RX path: USB OUT FIFO → APB read ----
    assign usb_out_ready = apb_rd & sel_data & usb_out_valid;

    // ---- PREADY ----
    wire pready_wr = ~(apb_wr & sel_data & tx_pending);
    wire pready_rd = ~(apb_rd & sel_data & ~usb_out_valid);
    assign PREADY = pready_wr & pready_rd;

    // ---- PRDATA ----
    assign PRDATA = sel_status ? {30'd0, usb_out_valid, usb_in_ready} :
                    sel_data   ? {24'd0, usb_out_data} :
                    32'd0;

endmodule
