`timescale 1ns/1ps

module entropy_core (
    input  wire en,

    // Outputs to sampler
    output wire s1,
    output wire s2,
    output wire s3
);

    // ============================================================
    // Internal wires from HCCLG blocks
    // ============================================================

    wire h1_out1, h1_out2;
    wire h2_out1, h2_out2;

    // ============================================================
    // Instantiate 2 HCCLG blocks
    // ============================================================

    hcclg u_hcclg_1 (
        .en(en),
        .out1(h1_out1),
        .out2(h1_out2)
    );

    hcclg u_hcclg_2 (
        .en(en),
        .out1(h2_out1),
        .out2(h2_out2)
    );

    // ============================================================
    // XOR mixing stage (B-XOR-LG)
    // ============================================================

    b_xor_lg u_bxor (
        .in1(h2_out1),
        .in2(h1_out1),
        .in3(h2_out2),
        .in4(h1_out2),
        .out1(s1),
        .out2(s2),
        .out3(s3)
    );

endmodule