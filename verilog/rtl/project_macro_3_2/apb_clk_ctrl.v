// SPDX-License-Identifier: Apache-2.0
// apb_clk_ctrl — APB slave for clock control registers
//
// Register map (word-aligned offsets):
//   0x00 : CTRL
//          [0]   fll_en        FLL enable (default 0)
//          [1]   rc16m_en      16M RC OSC enable (default 0)
//          [2]   rc500k_en     500k RC OSC enable (default 0)
//          [5:3] sel_mon       Monitor mux select (default 000)
//          [6]   fll_bypass    Bypass FLL, use xclk as USB clock (default 0)
//          [7]   RESERVED
//          [8]   usb_rst_n     USB reset, active-low (default 1)
//   0x04 : FLL_DIV
//          [7:0] fll_div       FLL feedback divider {5 int, 3 frac} (default 0)
//   0x08 : FLL_DCO
//          [0]   fll_dco       DCO mode enable (default 0)
//          [1]   RESERVED
//          [27:2] fll_ext_trim DCO external trim [25:0] (default 0)
//   0x0C : FLL_MON_DIV   [15:0] FLL output monitor divider (default 0)
//   0x10 : RC16M_MON_DIV [15:0] 16M RC OSC monitor divider   (default 0)
//   0x14 : RC500K_MON_DIV[15:0] 500k RC OSC monitor divider  (default 0)
//   0x18 : CLK_MON_DIV   [15:0] Monitor mux output divider   (default 0)
//   0x1C : MON_EN
//          [0] fll_mon_en     (default 0)
//          [1] rc16m_mon_en   (default 0)
//          [2] rc500k_mon_en  (default 0)
//          [3] clk_mon_en     (default 0)
//          [4] clk48m_mon_en  (default 0)
//   0x20 : USB_PAD
//          [2:0] usb_dp_dm    D+ pad drive mode  (default 110)
//          [5:3] usb_dn_dm    D- pad drive mode  (default 110)
//          [8:6] usb_pu_dm    PU pad drive mode  (default 110)

`timescale 1ns / 1ps
`default_nettype none

module apb_clk_ctrl (
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

    output reg          fll_en,
    output reg          rc16m_en,
    output reg          rc500k_en,
    output reg   [2:0]  sel_mon,
    output reg          fll_bypass,
    output reg          usb_rst_n,
    output reg   [7:0]  fll_div,
    output reg          fll_dco,
    output reg   [25:0] fll_ext_trim,
    output reg   [15:0] fll_mon_div,
    output reg   [15:0] rc16m_mon_div,
    output reg   [15:0] rc500k_mon_div,
    output reg   [15:0] clk_mon_div,
    output reg          fll_mon_en,
    output reg          rc16m_mon_en,
    output reg          rc500k_mon_en,
    output reg          clk_mon_en,
    output reg          clk48m_mon_en,
    output reg   [2:0]  usb_dp_dm,
    output reg   [2:0]  usb_dn_dm,
    output reg   [2:0]  usb_pu_dm
);

    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    wire apb_wr = PSEL & PENABLE & PWRITE;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fll_en         <= 1'b0;
            rc16m_en       <= 1'b0;
            rc500k_en      <= 1'b0;
            sel_mon        <= 3'd0;
            fll_bypass     <= 1'b0;
            usb_rst_n      <= 1'b1;
            fll_div        <= 8'd0;
            fll_dco        <= 1'b0;
            fll_ext_trim   <= 26'd0;
            fll_mon_div    <= 16'd0;
            rc16m_mon_div  <= 16'd0;
            rc500k_mon_div <= 16'd0;
            clk_mon_div    <= 16'd0;
            fll_mon_en     <= 1'b0;
            rc16m_mon_en   <= 1'b0;
            rc500k_mon_en  <= 1'b0;
            clk_mon_en     <= 1'b0;
            clk48m_mon_en  <= 1'b0;
            usb_dp_dm      <= 3'b110;
            usb_dn_dm      <= 3'b110;
            usb_pu_dm      <= 3'b110;
        end else if (apb_wr) begin
            case (PADDR)
                13'h00: begin
                    fll_en     <= PWDATA[0];
                    rc16m_en   <= PWDATA[1];
                    rc500k_en  <= PWDATA[2];
                    sel_mon    <= PWDATA[5:3];
                    fll_bypass <= PWDATA[6];
                    usb_rst_n  <= PWDATA[8];
                end
                13'h04: fll_div      <= PWDATA[7:0];
                13'h08: begin
                    fll_dco      <= PWDATA[0];
                    fll_ext_trim <= PWDATA[27:2];
                end
                13'h0C: fll_mon_div    <= PWDATA[15:0];
                13'h10: rc16m_mon_div  <= PWDATA[15:0];
                13'h14: rc500k_mon_div <= PWDATA[15:0];
                13'h18: clk_mon_div    <= PWDATA[15:0];
                13'h1C: begin
                    fll_mon_en    <= PWDATA[0];
                    rc16m_mon_en  <= PWDATA[1];
                    rc500k_mon_en <= PWDATA[2];
                    clk_mon_en    <= PWDATA[3];
                    clk48m_mon_en <= PWDATA[4];
                end
                13'h20: begin
                    usb_dp_dm <= PWDATA[2:0];
                    usb_dn_dm <= PWDATA[5:3];
                    usb_pu_dm <= PWDATA[8:6];
                end
                default: ;
            endcase
        end
    end

    always @(*) begin
        case (PADDR)
            13'h00: PRDATA = {23'd0, usb_rst_n, 1'b0, fll_bypass, sel_mon, rc500k_en, rc16m_en, fll_en};
            13'h04: PRDATA = {24'd0, fll_div};
            13'h08: PRDATA = {4'd0, fll_ext_trim, 1'b0, fll_dco};
            13'h0C: PRDATA = {16'd0, fll_mon_div};
            13'h10: PRDATA = {16'd0, rc16m_mon_div};
            13'h14: PRDATA = {16'd0, rc500k_mon_div};
            13'h18: PRDATA = {16'd0, clk_mon_div};
            13'h1C: PRDATA = {27'd0, clk48m_mon_en, clk_mon_en, rc500k_mon_en, rc16m_mon_en, fll_mon_en};
            13'h20: PRDATA = {23'd0, usb_pu_dm, usb_dn_dm, usb_dp_dm};
            default: PRDATA = 32'd0;
        endcase
    end

endmodule
