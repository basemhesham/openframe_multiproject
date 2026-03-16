// SPDX-License-Identifier: Apache-2.0
// Technology Abstraction: Integrated Clock Gating Cell

`default_nettype none

module tech_clkgate (
    input  wire CLK,
    input  wire GATE,
    output wire GCLK
);

`ifdef SKY130
    (* dont_touch = "true" *) sky130_fd_sc_hd__dlclkp_1 _icg (.CLK(CLK), .GATE(GATE), .GCLK(GCLK));
`elsif GF180
    (* dont_touch = "true" *) gf180mcu_fd_sc_mcu7t5v0__icg _icg (.CLK(CLK), .GATE(GATE), .GCLK(GCLK));
`else
    reg latch_en;
    always @(*) if (!CLK) latch_en <= GATE;
    assign GCLK = CLK & latch_en;
`endif

endmodule
