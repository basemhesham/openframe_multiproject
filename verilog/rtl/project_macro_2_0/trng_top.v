`timescale 1ns/1ps

module trng_top (
    input  wire clk,
    input  wire en,

    // Output sampled entropy directly
    output wire q1,
    output wire q2,
    output wire q3
);

    // ============================================================
    // Internal wires
    // ============================================================

    // From entropy core
    wire s1, s2, s3;

    // ============================================================
    // Entropy core
    // ============================================================

    entropy_core u_entropy (
        .en(en),
        .s1(s1),
        .s2(s2),
        .s3(s3)
    );

    // ============================================================
    // Sampler
    // ============================================================

    sampler u_sampler (
        .clk(clk),
        .in1(s1),
        .in2(s2),
        .in3(s3),
        .q1(q1),
        .q2(q2),
        .q3(q3)
    );

endmodule