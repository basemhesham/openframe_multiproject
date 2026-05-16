// SPDX-License-Identifier: Apache-2.0
// apb_status — Read-only APB slave exposing synchronised status signals
//
// Register map (word-aligned offsets):
//   0x00 : STATUS
//          [0]   fll_active      (FLL output toggling)
//          [1]   fll_clk48m_active (FLL/2 output toggling)
//          [2]   rc16m_active
//          [3]   rc500k_active
//          [4]   fll_en_reg
//          [5]   rc16m_en_reg
//          [6]   rc500k_en_reg
//          [9:7] sel_mon
//          [10]  fll_bypass
//   0x04 : FLL freq counter — FLL clk edges in last window
//   0x08 : RC16M freq counter — RC16M clk edges in last window
//   0x0C : REF freq counter — xclk edges in last window
//   0x10 : IRQ status — synchronised peripheral interrupt-request lines
//          [0]  irq_attoio   (AttoIO irq_to_host)
//          [1]  irq_sercom   (nc_sercom irq_o)
//          [31:2] reserved
//          Read-only. Bits clear when the source peripheral deasserts.

`timescale 1ns / 1ps
`default_nettype none

module apb_status #(
    parameter CNT_WINDOW = 32'd1_000_000
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire  [12:0] PADDR,
    input  wire         PSEL,
    input  wire         PENABLE,
    input  wire         PWRITE,
    input  wire  [31:0] PWDATA,
    output reg   [31:0] PRDATA,
    output wire         PREADY,
    output wire         PSLVERR,

    input  wire         fll_clk96m_in,
    input  wire         fll_clk48m_in,
    input  wire         rc16m_clk_in,
    input  wire         rc500k_clk_in,
    input  wire         fll_en_sts,
    input  wire         rc16m_en_sts,
    input  wire         rc500k_en_sts,
    input  wire  [2:0]  sel_mon_sts,
    input  wire         fll_bypass_sts,
    input  wire         irq_attoio_in,
    input  wire         irq_sercom_in
);

    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    reg [1:0] fll96m_sync, fll48m_sync, rc16m_sync, rc500k_sync;
    reg [1:0] irq_attoio_sync, irq_sercom_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fll96m_sync     <= 2'b00;
            fll48m_sync     <= 2'b00;
            rc16m_sync      <= 2'b00;
            rc500k_sync     <= 2'b00;
            irq_attoio_sync <= 2'b00;
            irq_sercom_sync <= 2'b00;
        end else begin
            fll96m_sync     <= {fll96m_sync[0],     fll_clk96m_in};
            fll48m_sync     <= {fll48m_sync[0],     fll_clk48m_in};
            rc16m_sync      <= {rc16m_sync[0],      rc16m_clk_in};
            rc500k_sync     <= {rc500k_sync[0],     rc500k_clk_in};
            irq_attoio_sync <= {irq_attoio_sync[0], irq_attoio_in};
            irq_sercom_sync <= {irq_sercom_sync[0], irq_sercom_in};
        end
    end

    reg fll96m_prev, rc16m_prev;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fll96m_prev <= 1'b0;
            rc16m_prev  <= 1'b0;
        end else begin
            fll96m_prev <= fll96m_sync[1];
            rc16m_prev  <= rc16m_sync[1];
        end
    end

    wire fll96m_rise = fll96m_sync[1] & ~fll96m_prev;
    wire rc16m_rise  = rc16m_sync[1]  & ~rc16m_prev;

    reg [31:0] window_cnt;
    reg [31:0] fll_cnt, fll_cnt_latch;
    reg [31:0] rc16m_cnt, rc16m_cnt_latch;
    reg [31:0] ref_cnt, ref_cnt_latch;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            window_cnt    <= 32'd0;
            fll_cnt       <= 32'd0;
            fll_cnt_latch <= 32'd0;
            rc16m_cnt     <= 32'd0;
            rc16m_cnt_latch <= 32'd0;
            ref_cnt       <= 32'd0;
            ref_cnt_latch <= 32'd0;
        end else begin
            if (window_cnt >= CNT_WINDOW - 32'd1) begin
                window_cnt      <= 32'd0;
                fll_cnt_latch   <= fll_cnt;
                rc16m_cnt_latch <= rc16m_cnt;
                ref_cnt_latch   <= ref_cnt;
                fll_cnt   <= fll96m_rise ? 32'd1 : 32'd0;
                rc16m_cnt <= rc16m_rise  ? 32'd1 : 32'd0;
                ref_cnt   <= 32'd1;
            end else begin
                window_cnt <= window_cnt + 32'd1;
                fll_cnt    <= fll_cnt + (fll96m_rise ? 32'd1 : 32'd0);
                rc16m_cnt  <= rc16m_cnt + (rc16m_rise ? 32'd1 : 32'd0);
                ref_cnt    <= ref_cnt + 32'd1;
            end
        end
    end

    always @(*) begin
        case (PADDR)
            13'h00: PRDATA = {21'd0, fll_bypass_sts, sel_mon_sts,
                              rc500k_en_sts, rc16m_en_sts, fll_en_sts,
                              rc500k_sync[1], rc16m_sync[1],
                              fll48m_sync[1], fll96m_sync[1]};
            13'h04: PRDATA = fll_cnt_latch;
            13'h08: PRDATA = rc16m_cnt_latch;
            13'h0C: PRDATA = ref_cnt_latch;
            13'h10: PRDATA = {30'd0, irq_sercom_sync[1], irq_attoio_sync[1]};
            default: PRDATA = 32'd0;
        endcase
    end

endmodule
