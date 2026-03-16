// SPDX-License-Identifier: Apache-2.0
// tb_scan_node — Unit test for scan_macro_node
//
// Tests both WIDTH=1 and WIDTH=3 configurations:
//   - POR clears shadow_reg
//   - Shift/latch functionality
//   - Shift without latch doesn't affect shadow
//   - Clock/latch passthrough buffering
//   - scan_out reflects shift_reg MSB

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
    reg  w1_scan_clk_in, w1_scan_latch_in, w1_scan_in;
    wire w1_scan_clk_out, w1_scan_latch_out, w1_scan_out;
    wire w1_ctrl_out;

    scan_macro_node #(.WIDTH(1)) dut_w1 (
        .por_n          (w1_por_n),
        .scan_clk_in    (w1_scan_clk_in),
        .scan_latch_in  (w1_scan_latch_in),
        .scan_in        (w1_scan_in),
        .scan_clk_out   (w1_scan_clk_out),
        .scan_latch_out (w1_scan_latch_out),
        .scan_out       (w1_scan_out),
        .ctrl_out       (w1_ctrl_out)
    );

    // -----------------------------------------------------------------
    // DUT instance: WIDTH=3
    // -----------------------------------------------------------------
    reg  w3_por_n;
    reg  w3_scan_clk_in, w3_scan_latch_in, w3_scan_in;
    wire w3_scan_clk_out, w3_scan_latch_out, w3_scan_out;
    wire [2:0] w3_ctrl_out;

    scan_macro_node #(.WIDTH(3)) dut_w3 (
        .por_n          (w3_por_n),
        .scan_clk_in    (w3_scan_clk_in),
        .scan_latch_in  (w3_scan_latch_in),
        .scan_in        (w3_scan_in),
        .scan_clk_out   (w3_scan_clk_out),
        .scan_latch_out (w3_scan_latch_out),
        .scan_out       (w3_scan_out),
        .ctrl_out       (w3_ctrl_out)
    );

    // Helper: shift one bit into W=1 DUT
    task w1_shift;
        input val;
        begin
            w1_scan_in = val;
            @(posedge w1_scan_clk_in);
            #1;
        end
    endtask

    // Helper: shift one bit into W=3 DUT
    task w3_shift;
        input val;
        begin
            w3_scan_in = val;
            @(posedge w3_scan_clk_in);
            #1;
        end
    endtask

    // Clocks
    initial w1_scan_clk_in = 0;
    always #50 w1_scan_clk_in = ~w1_scan_clk_in;
    initial w3_scan_clk_in = 0;
    always #50 w3_scan_clk_in = ~w3_scan_clk_in;

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
        w1_scan_in = 1'b0;
        w1_scan_latch_in = 1'b0;
        #100;
        assert_eq(w1_ctrl_out, 0, "W1: POR shadow_reg");
        w1_por_n = 1'b1;
        #10;

        // Test 1.2: Shift in 1, verify scan_out
        $display("[1.2] Shift 1'b1, verify scan_out");
        w1_shift(1'b1);
        assert_eq(w1_scan_out, 1, "W1: scan_out after shift 1");
        assert_eq(w1_ctrl_out, 0, "W1: shadow unchanged without latch");

        // Test 1.3: Latch
        $display("[1.3] Latch -> shadow captures");
        w1_scan_latch_in = 1'b1;
        @(posedge w1_scan_clk_in);
        #1;
        w1_scan_latch_in = 1'b0;
        #1;
        assert_eq(w1_ctrl_out, 1, "W1: shadow_reg after latch");

        // Test 1.4: Shift 0, no latch -> shadow stays 1
        $display("[1.4] Shift 0, no latch -> shadow unchanged");
        w1_shift(1'b0);
        assert_eq(w1_scan_out, 0, "W1: scan_out after shift 0");
        assert_eq(w1_ctrl_out, 1, "W1: shadow unchanged");

        // Test 1.5: POR clears shadow
        $display("[1.5] POR clears shadow even with shift_reg loaded");
        w1_por_n = 1'b0;
        @(posedge w1_scan_clk_in);
        #1;
        assert_eq(w1_ctrl_out, 0, "W1: POR clears shadow");
        w1_por_n = 1'b1;
        #10;

        // Test 1.6: Clock passthrough
        $display("[1.6] Clock/latch passthrough");
        // scan_clk_out and scan_latch_out are buffered copies
        // In behavioral mode (no SKY130), they should equal the inputs
        w1_scan_latch_in = 1'b1;
        #1;
        assert_eq(w1_scan_latch_out, 1, "W1: latch passthrough high");
        w1_scan_latch_in = 1'b0;
        #1;
        assert_eq(w1_scan_latch_out, 0, "W1: latch passthrough low");

        // =====================================================================
        // WIDTH=3 Tests
        // =====================================================================
        $display("\n=== WIDTH=3 Tests ===");

        // Test 2.1: POR
        $display("[2.1] POR clears shadow_reg[2:0]");
        w3_por_n = 1'b0;
        w3_scan_in = 1'b0;
        w3_scan_latch_in = 1'b0;
        #100;
        assert_eq_vec(w3_ctrl_out, 3'b000, "W3: POR shadow_reg");
        w3_por_n = 1'b1;
        #10;

        // Test 2.2: Shift 3'b101 (MSB first: 1, 0, 1)
        // After 3 shifts: shift_reg = {0, scan_in=1} -> {shift_reg[1:0], scan_in}
        // Shift 1: shift_reg = xxx -> {xx, 1} (first bit goes to [0], unknown above)
        // Shift 0: shift_reg = {x, 1, 0} -> bit[1]=1 from prior, bit[0]=0
        // Shift 1: shift_reg = {1, 0, 1} -> bit[2]=1, bit[1]=0, bit[0]=1
        // scan_out = shift_reg[2] = 1
        $display("[2.2] Shift 3'b101 (MSB first: 1,0,1)");
        w3_shift(1'b1);  // goes to [0]
        w3_shift(1'b0);  // prior[0] moves to [1], new 0 at [0]
        w3_shift(1'b1);  // prior[1:0]={1,0} moves to [2:1], new 1 at [0]
        // shift_reg should be: [2]=1, [1]=0, [0]=1 = 3'b101
        assert_eq(w3_scan_out, 1, "W3: scan_out = shift_reg[2] = 1");
        assert_eq_vec(w3_ctrl_out, 3'b000, "W3: shadow unchanged");

        // Test 2.3: Latch
        $display("[2.3] Latch -> shadow=3'b101");
        w3_scan_latch_in = 1'b1;
        @(posedge w3_scan_clk_in);
        #1;
        w3_scan_latch_in = 1'b0;
        #1;
        assert_eq_vec(w3_ctrl_out, 3'b101, "W3: shadow after latch");

        // Test 2.4: Shift new value without latch
        $display("[2.4] Shift 3'b010 without latch -> shadow unchanged");
        w3_shift(1'b0);
        w3_shift(1'b1);
        w3_shift(1'b0);
        assert_eq_vec(w3_ctrl_out, 3'b101, "W3: shadow still 101");
        assert_eq(w3_scan_out, 0, "W3: scan_out = shift_reg[2] = 0");

        // Test 2.5: POR clears shadow but shift_reg has no reset
        $display("[2.5] POR clears shadow only");
        w3_por_n = 1'b0;
        @(posedge w3_scan_clk_in);
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
