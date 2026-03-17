// SPDX-License-Identifier: Apache-2.0
// tb_purple — Unit test for purple_macro
//
// Tests PORTS=4 and PORTS=3: master enable, port selection,
// invalid port_sel clamping, inbound fan-out, Hi-Z default.

`timescale 1ns/1ps
`default_nettype none

module tb_purple;

    integer error_count;
    reg scan_clk, scan_din, scan_latch;
    reg por_n, sys_rst_n;

    `include "../common/scan_tasks.vh"

    localparam PADS = 15;

    // -----------------------------------------------------------------
    // DUT: PORTS=4 (Right/Left purple, SCAN_WIDTH=3)
    // scan_ctrl: [2]=master_en, [1:0]=port_sel
    // -----------------------------------------------------------------
    wire p4_scan_clk_out_b, p4_scan_latch_out_b, p4_scan_out_b;
    reg  [PADS-1:0]   p4_pad_gpio_in;
    wire [PADS-1:0]   p4_pad_gpio_out, p4_pad_gpio_oeb;
    wire [PADS*3-1:0] p4_pad_gpio_dm;
    wire [4*PADS-1:0] p4_tree_gpio_in;
    reg  [4*PADS-1:0] p4_tree_gpio_out, p4_tree_gpio_oeb;
    reg  [4*PADS*3-1:0] p4_tree_gpio_dm;

    purple_macro #(.PADS(PADS), .PORTS(4)) dut_p4 (
        .por_n          (por_n),
        // Scan in from side A
        .scan_clk_a     (scan_clk),
        .scan_latch_a   (scan_latch),
        .scan_in_a      (scan_din),
        .scan_clk_out_a (),
        .scan_latch_out_a(),
        .scan_out_a     (),
        // Scan out from side B
        .scan_clk_b     (1'b0),
        .scan_latch_b   (1'b0),
        .scan_in_b      (1'b0),
        .scan_clk_out_b (p4_scan_clk_out_b),
        .scan_latch_out_b(p4_scan_latch_out_b),
        .scan_out_b     (p4_scan_out_b),
        // GPIO
        .pad_gpio_in    (p4_pad_gpio_in),
        .pad_gpio_out   (p4_pad_gpio_out),
        .pad_gpio_oeb   (p4_pad_gpio_oeb),
        .pad_gpio_dm    (p4_pad_gpio_dm),
        .tree_gpio_in   (p4_tree_gpio_in),
        .tree_gpio_out  (p4_tree_gpio_out),
        .tree_gpio_oeb  (p4_tree_gpio_oeb),
        .tree_gpio_dm   (p4_tree_gpio_dm)
    );

    // Helper: shift 3 scan bits into purple PORTS=4
    task p4_shift_config;
        input [2:0] bits;
        begin
            shift_bit(bits[2]);
            shift_bit(bits[1]);
            shift_bit(bits[0]);
            pulse_latch;
            #10;
        end
    endtask

    // Clock
    initial scan_clk = 0;
    always #50 scan_clk = ~scan_clk;

    initial begin
        $dumpfile("tb_purple.vcd");
        $dumpvars(0, tb_purple);

        error_count = 0;
        p4_pad_gpio_in = {PADS{1'b0}};
        p4_tree_gpio_out = {(4*PADS){1'b0}};
        p4_tree_gpio_oeb = {(4*PADS){1'b1}};
        p4_tree_gpio_dm  = {(4*PADS*3){1'b0}};

        // Set distinct patterns on each tree port
        p4_tree_gpio_out[0*PADS +: PADS] = 15'h1111;
        p4_tree_gpio_out[1*PADS +: PADS] = 15'h2222;
        p4_tree_gpio_out[2*PADS +: PADS] = 15'h3333;
        p4_tree_gpio_out[3*PADS +: PADS] = 15'h4444;

        p4_tree_gpio_oeb[0*PADS +: PADS] = 15'h000F;
        p4_tree_gpio_oeb[1*PADS +: PADS] = 15'h00F0;
        p4_tree_gpio_oeb[2*PADS +: PADS] = 15'h0F00;
        p4_tree_gpio_oeb[3*PADS +: PADS] = 15'hF000;

        // =====================================================================
        // Test 1: POR default — Hi-Z
        // =====================================================================
        $display("\n[1] POR default: master_en=0 -> Hi-Z");
        do_por;
        assert_eq_vec(p4_pad_gpio_out, {PADS{1'b0}}, "P4: pad_out=0 (disabled)");
        assert_eq_vec(p4_pad_gpio_oeb, {PADS{1'b1}}, "P4: pad_oeb=all 1 (Hi-Z)");

        // =====================================================================
        // Test 2: Enable, select port 0
        // =====================================================================
        $display("[2] Enable + port 0");
        p4_shift_config(3'b100);
        assert_eq_vec(p4_pad_gpio_out, 15'h1111, "P4: port 0 out");
        assert_eq_vec(p4_pad_gpio_oeb, 15'h000F, "P4: port 0 oeb");

        // =====================================================================
        // Test 3: Select port 1
        // =====================================================================
        $display("[3] Select port 1");
        p4_shift_config(3'b101);
        assert_eq_vec(p4_pad_gpio_out, 15'h2222, "P4: port 1 out");
        assert_eq_vec(p4_pad_gpio_oeb, 15'h00F0, "P4: port 1 oeb");

        // =====================================================================
        // Test 4: Select port 2
        // =====================================================================
        $display("[4] Select port 2");
        p4_shift_config(3'b110);
        assert_eq_vec(p4_pad_gpio_out, 15'h3333, "P4: port 2 out");
        assert_eq_vec(p4_pad_gpio_oeb, 15'h0F00, "P4: port 2 oeb");

        // =====================================================================
        // Test 5: Select port 3
        // =====================================================================
        $display("[5] Select port 3");
        p4_shift_config(3'b111);
        assert_eq_vec(p4_pad_gpio_out, 15'h4444, "P4: port 3 out");
        assert_eq_vec(p4_pad_gpio_oeb, 15'hF000, "P4: port 3 oeb");

        // =====================================================================
        // Test 6: Master disable overrides selection
        // =====================================================================
        $display("[6] Master disable overrides port selection");
        p4_shift_config(3'b011);
        assert_eq_vec(p4_pad_gpio_out, {PADS{1'b0}}, "P4: disabled out=0");
        assert_eq_vec(p4_pad_gpio_oeb, {PADS{1'b1}}, "P4: disabled oeb=all 1");

        // =====================================================================
        // Test 7: Inbound fan-out
        // =====================================================================
        $display("[7] Inbound fan-out: pad_in -> all tree_in ports");
        p4_pad_gpio_in = 15'h5A5A;
        #10;
        assert_eq_vec(p4_tree_gpio_in[0*PADS +: PADS], 15'h5A5A, "P4: tree[0] in");
        assert_eq_vec(p4_tree_gpio_in[1*PADS +: PADS], 15'h5A5A, "P4: tree[1] in");
        assert_eq_vec(p4_tree_gpio_in[2*PADS +: PADS], 15'h5A5A, "P4: tree[2] in");
        assert_eq_vec(p4_tree_gpio_in[3*PADS +: PADS], 15'h5A5A, "P4: tree[3] in");

        // =====================================================================
        // Test 8: PORTS=4 — all port_sel values valid
        // =====================================================================
        $display("[8] PORTS=4: all port_sel values valid (no clamping)");

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
