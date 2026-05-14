`timescale 1ns/1ps

(* dont_touch = "true" *)
module hcclg (
    input  wire en,
    output wire out1,
    output wire out2
);

    // ============================================================
    // Internal wires (protected feedback paths)
    // ============================================================

    // Upper branch
    (* keep *) wire upper_nand_out;
    (* keep *) wire upper_inv1_out;
    (* keep *) wire upper_inv2_out;

    // Lower branch
    (* keep *) wire lower_nand_out;
    (* keep *) wire lower_inv1_out;
    (* keep *) wire lower_inv2_out;

    // Inputs to CCX stage
    (* keep *) wire temp1;
    (* keep *) wire temp2;

    // ============================================================
    // LEFT SIDE: Local feedback loops (correct per your diagram)
    // ============================================================

    // Upper NAND
    (* dont_touch = "true" *)
    sky130_fd_sc_hd__nand2_1 u_upper_nand (
        .A(en),
        .B(upper_inv2_out),
        .Y(upper_nand_out)
    );

    // Upper inverter chain
    (* dont_touch = "true" *)
    sky130_fd_sc_hd__inv_1 u_upper_inv1 (
        .A(upper_nand_out),
        .Y(upper_inv1_out)
    );

    (* dont_touch = "true" *)
    sky130_fd_sc_hd__inv_1 u_upper_inv2 (
        .A(upper_inv1_out),
        .Y(upper_inv2_out)
    );

    // Lower NAND
    (* dont_touch = "true" *)
    sky130_fd_sc_hd__nand2_1 u_lower_nand (
        .A(en),
        .B(lower_inv2_out),
        .Y(lower_nand_out)
    );

    // Lower inverter chain
    (* dont_touch = "true" *)
    sky130_fd_sc_hd__inv_1 u_lower_inv1 (
        .A(lower_nand_out),
        .Y(lower_inv1_out)
    );

    (* dont_touch = "true" *)
    sky130_fd_sc_hd__inv_1 u_lower_inv2 (
        .A(lower_inv1_out),
        .Y(lower_inv2_out)
    );

    // ============================================================
    // Crossed taps into CCX stage
    // ============================================================

    assign temp1 = lower_nand_out;
    assign temp2 = upper_inv2_out;

    // ============================================================
    // RIGHT SIDE: Cross-coupled XOR stage
    // ============================================================

    (* dont_touch = "true" *)
    sky130_fd_sc_hd__xor2_1 u_xor_out1 (
        .A(temp1),
        .B(out2),
        .X(out1)
    );

    (* dont_touch = "true" *)
    sky130_fd_sc_hd__xor2_1 u_xor_out2 (
        .A(temp2),
        .B(out1),
        .X(out2)
    );

endmodule