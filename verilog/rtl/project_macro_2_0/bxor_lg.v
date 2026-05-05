`timescale 1ns/1ps

(* dont_touch = "true" *)
module b_xor_lg (
    input  wire in1,
    input  wire in2,
    input  wire in3,
    input  wire in4,
    output wire out1,
    output wire out2,
    output wire out3 
);

    // ============================================================
    // Internal wires (feedback must be preserved)
    // ============================================================

    (* keep *) wire wire_from_a_to_1;
    (* keep *) wire wire_from_b_to_2;
    (* keep *) wire out_gate_1;
    (* keep *) wire out_gate_2;

    // ============================================================
    // Feedback XOR network
    // ============================================================

    // Gate A
    (* dont_touch = "true" *)
    sky130_fd_sc_hd__xor3_1 gate_a (
        .A(in1),
        .B(out_gate_1),
        .C(in3),
        .X(wire_from_a_to_1)
    );

    // Gate B
    (* dont_touch = "true" *)
    sky130_fd_sc_hd__xor3_1 gate_b (
        .A(in2),
        .B(out_gate_2),
        .C(in4),
        .X(wire_from_b_to_2)
    );

    // Gate 1
    (* dont_touch = "true" *)
    sky130_fd_sc_hd__xor2_1 gate_1 (
        .A(wire_from_a_to_1),
        .B(in2),
        .X(out_gate_1)
    );

    // Gate 2
    (* dont_touch = "true" *)
    sky130_fd_sc_hd__xor2_1 gate_2 (
        .A(in3),
        .B(wire_from_b_to_2),
        .X(out_gate_2)
    );

    // ============================================================
    // Output stage
    // ============================================================

    (* dont_touch = "true" *)
    sky130_fd_sc_hd__xor2_1 gate_3 (
        .A(in4),
        .B(out_gate_1),
        .X(out1)
    );

    (* dont_touch = "true" *)
    sky130_fd_sc_hd__xor2_1 gate_4 (
        .A(in1),
        .B(in4),
        .X(out2)
    );

    (* dont_touch = "true" *)
    sky130_fd_sc_hd__xor2_1 gate_5 (
        .A(in1),
        .B(out_gate_2),
        .X(out3)
    );

endmodule