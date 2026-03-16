// SPDX-License-Identifier: Apache-2.0
// tb_green — Unit test for green_macro
//
// Tests: clock gating, reset gating, scan node enable/disable,
// column chain passthrough.

`timescale 1ns/1ps
`default_nettype none

module tb_green;

    integer error_count;
    reg scan_clk, scan_din, scan_latch;
    reg por_n, sys_rst_n;

    `include "../common/scan_tasks.vh"

    // DUT signals
    reg  sys_clk_in, sys_reset_n_in;
    wire sys_clk_out, sys_reset_n_out;
    wire proj_clk_out, proj_reset_n_out, proj_por_n_out;
    wire scan_clk_out, scan_latch_out, scan_out;

    green_macro dut (
        .sys_clk_in      (sys_clk_in),
        .sys_reset_n_in  (sys_reset_n_in),
        .sys_clk_out     (sys_clk_out),
        .sys_reset_n_out (sys_reset_n_out),
        .proj_clk_out    (proj_clk_out),
        .proj_reset_n_out(proj_reset_n_out),
        .proj_por_n_out  (proj_por_n_out),
        .por_n           (por_n),
        .scan_clk_in     (scan_clk),
        .scan_latch_in   (scan_latch),
        .scan_in         (scan_din),
        .scan_clk_out    (scan_clk_out),
        .scan_latch_out  (scan_latch_out),
        .scan_out        (scan_out)
    );

    // Clocks
    initial sys_clk_in = 0;
    always #5 sys_clk_in = ~sys_clk_in;
    initial scan_clk = 0;
    always #50 scan_clk = ~scan_clk;

    // Count proj_clk_out edges
    integer proj_clk_edges;
    always @(posedge proj_clk_out) proj_clk_edges = proj_clk_edges + 1;

    initial begin
        $dumpfile("tb_green.vcd");
        $dumpvars(0, tb_green);

        error_count = 0;
        sys_reset_n_in = 1'b1;
        proj_clk_edges = 0;

        // =====================================================================
        // Test 1: POR clears proj_en
        // =====================================================================
        $display("\n[1] POR clears proj_en");
        do_por;
        sys_reset_n_in = 1'b1;
        assert_eq(dut.u_node.shadow_reg, 0, "proj_en=0 after POR");

        // =====================================================================
        // Test 2: Clock gating when disabled
        // =====================================================================
        $display("[2] Clock gated when proj_en=0");
        proj_clk_edges = 0;
        #200;  // Wait for ~20 sys_clk cycles
        assert_eq(proj_clk_edges, 0, "no proj_clk edges when disabled");

        // =====================================================================
        // Test 3: Reset gating when disabled
        // =====================================================================
        $display("[3] Reset held low when disabled");
        sys_reset_n_in = 1'b1;
        #10;
        assert_eq(proj_reset_n_out, 0, "proj_reset_n=0 when disabled (rst=1)");

        // =====================================================================
        // Test 4: Enable project via scan
        // =====================================================================
        $display("[4] Enable project via scan");
        shift_bit(1'b1);
        pulse_latch;
        #10;
        assert_eq(dut.u_node.shadow_reg, 1, "proj_en=1 after scan enable");

        // =====================================================================
        // Test 5: Clock passes when enabled
        // =====================================================================
        $display("[5] Clock passes when enabled");
        proj_clk_edges = 0;
        // Wait for ICG to latch the new GATE value
        @(negedge sys_clk_in); #1; // ICG latches on low phase
        @(posedge sys_clk_in); #1;
        proj_clk_edges = 0;
        #200;  // ~20 sys_clk cycles
        if (proj_clk_edges < 10) begin
            $display("  FAIL: proj_clk_out not toggling — only %0d edges", proj_clk_edges);
            error_count = error_count + 1;
        end else begin
            $display("  PASS: proj_clk_out toggling (%0d edges)", proj_clk_edges);
        end

        // =====================================================================
        // Test 6: Reset passes when enabled
        // =====================================================================
        $display("[6] Reset passes when enabled");
        sys_reset_n_in = 1'b1;
        #10;
        assert_eq(proj_reset_n_out, 1, "proj_reset_n=1 when enabled+rst=1");

        // =====================================================================
        // Test 7: Reset asserts when enabled
        // =====================================================================
        $display("[7] Reset asserts when enabled");
        sys_reset_n_in = 1'b0;
        #10;
        assert_eq(proj_reset_n_out, 0, "proj_reset_n=0 when enabled+rst=0");
        sys_reset_n_in = 1'b1;
        #10;

        // =====================================================================
        // Test 8: Column chain passthrough
        // =====================================================================
        $display("[8] Column chain passthrough");
        // sys_clk_out and sys_reset_n_out should be buffered copies
        // In behavioral mode, they just follow the inputs
        sys_reset_n_in = 1'b0;
        #1;
        assert_eq(sys_reset_n_out, 0, "sys_reset_n_out follows input low");
        sys_reset_n_in = 1'b1;
        #1;
        assert_eq(sys_reset_n_out, 1, "sys_reset_n_out follows input high");

        // =====================================================================
        // Test 9: POR passthrough to project
        // =====================================================================
        $display("[9] POR passthrough to project");
        assert_eq(proj_por_n_out, 1, "proj_por_n_out=1 when por_n=1");
        por_n = 1'b0;
        #10;
        assert_eq(proj_por_n_out, 0, "proj_por_n_out=0 when por_n=0");
        por_n = 1'b1;
        #10;
        assert_eq(proj_por_n_out, 1, "proj_por_n_out=1 after POR release");

        // Need to re-enable project for next test
        shift_bit(1'b1);
        pulse_latch;
        #10;
        @(negedge sys_clk_in); #1;
        @(posedge sys_clk_in); #1;

        // =====================================================================
        // Test 10: Disable mid-operation
        // =====================================================================
        $display("[10] Disable project mid-operation");
        shift_bit(1'b0);
        pulse_latch;
        #10;
        @(negedge sys_clk_in); #1; // Let ICG pick up new GATE
        @(posedge sys_clk_in); #1;
        proj_clk_edges = 0;
        #200;
        assert_eq(proj_clk_edges, 0, "proj_clk gated after disable");
        assert_eq(proj_reset_n_out, 0, "proj_reset_n=0 after disable");

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
        #100_000;
        $display("ERROR: Timeout!");
        $finish;
    end

endmodule
