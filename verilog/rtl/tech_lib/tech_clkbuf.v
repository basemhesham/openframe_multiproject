// SPDX-License-Identifier: Apache-2.0
// Technology Abstraction: Clock Tree Buffer

`default_nettype none

module tech_clkbuf (
    input  wire A,
    output wire X
);

`ifdef SKY130
    (* dont_touch = "true" *) sky130_fd_sc_hd__clkbuf_8 _buf (.X(X), .A(A));
`elsif GF180
    (* dont_touch = "true" *) gf180mcu_fd_sc_mcu7t5v0__clkbuf_4 _buf (.Z(X), .I(A));
`else
    assign X = A;
`endif

endmodule
