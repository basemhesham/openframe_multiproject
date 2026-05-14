`timescale 1ns/1ps

module sampler (
    input  wire clk,
    input  wire in1,
    input  wire in2,
    input  wire in3,
    output wire q1,
    output wire q2,
    output wire q3
);

    // ============================================================
    // 3 D Flip-Flops for sampling asynchronous entropy signals
    // ============================================================

    sky130_fd_sc_hd__dfxtp_1 u_dff1 (
        .CLK(clk),
        .D(in1),
        .Q(q1)
    );

    sky130_fd_sc_hd__dfxtp_1 u_dff2 (
        .CLK(clk),
        .D(in2),
        .Q(q2)
    );

    sky130_fd_sc_hd__dfxtp_1 u_dff3 (
        .CLK(clk),
        .D(in3),
        .Q(q3)
    );

endmodule