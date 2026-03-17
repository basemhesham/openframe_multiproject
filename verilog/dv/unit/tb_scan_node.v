// SPDX-License-Identifier: Apache-2.0
// tb_scan_node — Unit test for scan_macro_node
//
// Tests both WIDTH=1 and WIDTH=3 configurations:
//   - POR clears shadow_reg
//   - Shift/latch functionality
//   - Shift without latch doesn't affect shadow
//   - Clock/latch passthrough buffering (both sides)
//   - scan_out reflects shift_reg MSB on both sides

`timescale 1ns/1ps
`default_nettype none

module tb_scan_node;

    integer error_count;
    reg scan_clk, scan_din, scan_latch;
    reg por_n, sys_rst_n;

    `include "../common/scan_tasks.vh"

    // -----------------------------------------------------------------
    // DUT instance: WIDTH=1
    // -----------------------------------------------------------------
    reg  w1_por_n;
    reg  w1_scan_clk_a, w1_scan_latch_a, w1_scan_in_a;
    wire w1_scan_clk_out_a, w1_scan_latch_out_a, w1_scan_out_a;
    wire w1_scan_clk_out_b, w1_scan_latch_out_b, w1_scan_out_b;
    wire w1_ctrl_out;

    scan_macro_node #(.WIDTH(1)) dut_w1 (
        .por_n           (w1_por_n),
        .scan_clk_a      (w1_scan_clk_a),
        .scan_latch_a    (w1_scan_latch_a),
        .scan_in_a       (w1_scan_in_a),
        .scan_clk_out_a  (w1_scan_clk_out_a),
        .scan_latch_out_a(w1_scan_latch_out_a),
        .scan_out_a      (w1_scan_out_a),
        .scan_clk_b      (1'b0),
        .scan_latch_b    (1'b0),
        .scan_in_b       (1'b0),
        .scan_clk_out_b  (w1_scan_clk_out_b),
        .scan_latch_out_b(w1_scan_latch_out_b),
        .scan_out_b      (w1_scan_out_b),
        .ctrl_out        (w1_ctrl_out)
    );

    // -----------------------------------------------------------------
    // DUT instance: WIDTH=3
    // -----------------------------------------------------------------
    reg  w3_por_n;
    reg  w3_scan_clk_a, w3_scan_latch_a, w3_scan_in_a;
    wire w3_scan_clk_out_a, w3_scan_latch_out_a, w3_scan_out_a;
    wire w3_scan_clk_out_b, w3_scan_latch_out_b, w3_scan_out_b;
    wire [2:0] w3_ctrl_out;

    scan_macro_node #(.WIDTH(3)) dut_w3 (
        .por_n           (w3_por_n),
        .scan_clk_a      (w3_scan_clk_a),
        .scan_latch_a    (w3_scan_latch_a),
        .scan_in_a       (w3_scan_in_a),
        .scan_clk_out_a  (w3_scan_clk_out_a),
        .scan_latch_out_a(w3_scan_latch_out_a),
        .scan_out_a      (w3_scan_out_a),
        .scan_clk_b      (1'b0),
        .scan_latch_b    (1'b0),
        .scan_in_b       (1'b0),
        .scan_clk_out_b  (w3_scan_clk_out_b),
        .scan_latch_out_b(w3_scan_latch_out_b),
        .scan_out_b      (w3_scan_out_b),
        .ctrl_out        (w3_ctrl_out)
    );

    // Helper: shift one bit into W=1 DUT
    task w1_shift;
        input val;
        begin
            w1_scan_in_a = val;
            @(posedge w1_scan_clk_a);
            #1;
        end
    endtask

    // Helper: shift one bit into W=3 DUT
    task w3_shift;
        input val;
        begin
            w3_scan_in_a = val;
            @(posedge w3_scan_clk_a);
            #1;
        end
    endtask

    // Clocks
    initial w1_scan_clk_a = 0;
    always #50 w1_scan_clk_a = ~w1_scan_clk_a;
    initial w3_scan_clk_a = 0;
    always #50 w3_scan_clk_a = ~w3_scan_clk_a;

    initial begin
        $dumpfile("tb_scan_node.vcd");
        $dumpvars(0, tb_scan_node);

        error_count = 0;

        // =====================================================================
        // WIDTH=1 Tests
        // =====================================================================
        $display("\n=== WIDTH=1 Tests ===");

        // Test 1.1: POR clears shadow_reg
        $display("[1.1] POR clears shadow_reg");
        w1_por_n = 1'b0;
        w1_scan_in_a = 1'b0;
        w1_scan_latch_a = 1'b0;
        #100;
        assert_eq(w1_ctrl_out, 0, "W1: POR shadow_reg");
        w1_por_n = 1'b1;
        #10;

        // Test 1.2: Shift in 1, verify scan_out on both sides
        $display("[1.2] Shift 1'b1, verify scan_out on both sides");
        w1_shift(1'b1);
        assert_eq(w1_scan_out_a, 1, "W1: scan_out_a after shift 1");
        assert_eq(w1_scan_out_b, 1, "W1: scan_out_b after shift 1");
        assert_eq(w1_ctrl_out, 0, "W1: shadow unchanged without latch");

        // Test 1.3: Latch
        $display("[1.3] Latch -> shadow captures");
        w1_scan_latch_a = 1'b1;
        @(posedge w1_scan_clk_a);
        #1;
        w1_scan_latch_a = 1'b0;
        #1;
        assert_eq(w1_ctrl_out, 1, "W1: shadow_reg after latch");

        // Test 1.4: Shift 0, no latch -> shadow stays 1
        $display("[1.4] Shift 0, no latch -> shadow unchanged");
        w1_shift(1'b0);
        assert_eq(w1_scan_out_a, 0, "W1: scan_out_a after shift 0");
        assert_eq(w1_ctrl_out, 1, "W1: shadow unchanged");

        // Test 1.5: POR clears shadow
        $display("[1.5] POR clears shadow even with shift_reg loaded");
        w1_por_n = 1'b0;
        @(posedge w1_scan_clk_a);
        #1;
        assert_eq(w1_ctrl_out, 0, "W1: POR clears shadow");
        w1_por_n = 1'b1;
        #10;

        // Test 1.6: Clock/latch passthrough on both sides
        $display("[1.6] Clock/latch passthrough on both sides");
        w1_scan_latch_a = 1'b1;
        #1;
        assert_eq(w1_scan_latch_out_a, 1, "W1: latch_out_a high");
        assert_eq(w1_scan_latch_out_b, 1, "W1: latch_out_b high");
        w1_scan_latch_a = 1'b0;
        #1;
        assert_eq(w1_scan_latch_out_a, 0, "W1: latch_out_a low");
        assert_eq(w1_scan_latch_out_b, 0, "W1: latch_out_b low");

        // =====================================================================
        // WIDTH=3 Tests
        // =====================================================================
        $display("\n=== WIDTH=3 Tests ===");

        // Test 2.1: POR
        $display("[2.1] POR clears shadow_reg[2:0]");
        w3_por_n = 1'b0;
        w3_scan_in_a = 1'b0;
        w3_scan_latch_a = 1'b0;
        #100;
        assert_eq_vec(w3_ctrl_out, 3'b000, "W3: POR shadow_reg");
        w3_por_n = 1'b1;
        #10;

        // Test 2.2: Shift 3'b101 (MSB first: 1, 0, 1)
        $display("[2.2] Shift 3'b101 (MSB first: 1,0,1)");
        w3_shift(1'b1);
        w3_shift(1'b0);
        w3_shift(1'b1);
        assert_eq(w3_scan_out_a, 1, "W3: scan_out_a = shift_reg[2] = 1");
        assert_eq(w3_scan_out_b, 1, "W3: scan_out_b = shift_reg[2] = 1");
        assert_eq_vec(w3_ctrl_out, 3'b000, "W3: shadow unchanged");

        // Test 2.3: Latch
        $display("[2.3] Latch -> shadow=3'b101");
        w3_scan_latch_a = 1'b1;
        @(posedge w3_scan_clk_a);
        #1;
        w3_scan_latch_a = 1'b0;
        #1;
        assert_eq_vec(w3_ctrl_out, 3'b101, "W3: shadow after latch");

        // Test 2.4: Shift new value without latch
        $display("[2.4] Shift 3'b010 without latch -> shadow unchanged");
        w3_shift(1'b0);
        w3_shift(1'b1);
        w3_shift(1'b0);
        assert_eq_vec(w3_ctrl_out, 3'b101, "W3: shadow still 101");
        assert_eq(w3_scan_out_a, 0, "W3: scan_out_a = shift_reg[2] = 0");

        // Test 2.5: POR clears shadow but shift_reg has no reset
        $display("[2.5] POR clears shadow only");
        w3_por_n = 1'b0;
        @(posedge w3_scan_clk_a);
        #1;
        assert_eq_vec(w3_ctrl_out, 3'b000, "W3: POR clears shadow");
        w3_por_n = 1'b1;
        #10;

        // =====================================================================
        // Summary
        // =====================================================================
        #100;
        $display("\n============================================================");
        if (error_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("FAILED: %0d errors", error_count);
        $display("============================================================\n");
        $finish;
    end

    initial begin
        #50_000;
        $display("ERROR: Timeout!");
        $finish;
    end

endmodule
