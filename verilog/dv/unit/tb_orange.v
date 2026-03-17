// SPDX-License-Identifier: Apache-2.0
// tb_orange — Unit test for orange_macro
//
// Tests: POR default chain passthrough, select local project,
// MUX switching for out/oeb/dm, inbound broadcast, scan feedthrough.

`timescale 1ns/1ps
`default_nettype none

module tb_orange;

    integer error_count;
    reg scan_clk, scan_din, scan_latch;
    reg por_n, sys_rst_n;

    `include "../common/scan_tasks.vh"

    localparam PADS = 15;

    // DUT signals
    wire scan_clk_out_e, scan_latch_out_e, scan_out_e;

    reg  [PADS-1:0]   pad_side_gpio_in;
    wire [PADS-1:0]   pad_side_gpio_out;
    wire [PADS-1:0]   pad_side_gpio_oeb;
    wire [PADS*3-1:0] pad_side_gpio_dm;

    wire [PADS-1:0]   chain_side_gpio_in;
    reg  [PADS-1:0]   chain_side_gpio_out;
    reg  [PADS-1:0]   chain_side_gpio_oeb;
    reg  [PADS*3-1:0] chain_side_gpio_dm;

    wire [PADS-1:0]   local_proj_gpio_in;
    reg  [PADS-1:0]   local_proj_gpio_out;
    reg  [PADS-1:0]   local_proj_gpio_oeb;
    reg  [PADS*3-1:0] local_proj_gpio_dm;

    orange_macro #(.PADS(PADS)) dut (
        .por_n               (por_n),
        // Scan in from west side
        .scan_clk_w          (scan_clk),
        .scan_latch_w        (scan_latch),
        .scan_in_w           (scan_din),
        .scan_clk_out_w      (),
        .scan_latch_out_w    (),
        .scan_out_w          (),
        // Scan out from east side
        .scan_clk_e          (1'b0),
        .scan_latch_e        (1'b0),
        .scan_in_e           (1'b0),
        .scan_clk_out_e      (scan_clk_out_e),
        .scan_latch_out_e    (scan_latch_out_e),
        .scan_out_e          (scan_out_e),
        // GPIO
        .pad_side_gpio_in    (pad_side_gpio_in),
        .pad_side_gpio_out   (pad_side_gpio_out),
        .pad_side_gpio_oeb   (pad_side_gpio_oeb),
        .pad_side_gpio_dm    (pad_side_gpio_dm),
        .chain_side_gpio_in  (chain_side_gpio_in),
        .chain_side_gpio_out (chain_side_gpio_out),
        .chain_side_gpio_oeb (chain_side_gpio_oeb),
        .chain_side_gpio_dm  (chain_side_gpio_dm),
        .local_proj_gpio_in  (local_proj_gpio_in),
        .local_proj_gpio_out (local_proj_gpio_out),
        .local_proj_gpio_oeb (local_proj_gpio_oeb),
        .local_proj_gpio_dm  (local_proj_gpio_dm)
    );

    // Clock
    initial scan_clk = 0;
    always #50 scan_clk = ~scan_clk;

    initial begin
        $dumpfile("tb_orange.vcd");
        $dumpvars(0, tb_orange);

        error_count = 0;
        pad_side_gpio_in = {PADS{1'b0}};
        chain_side_gpio_out = {PADS{1'b0}};
        chain_side_gpio_oeb = {PADS{1'b1}};
        chain_side_gpio_dm = {(PADS*3){1'b0}};
        local_proj_gpio_out = {PADS{1'b0}};
        local_proj_gpio_oeb = {PADS{1'b1}};
        local_proj_gpio_dm = {(PADS*3){1'b0}};

        // =====================================================================
        // Test 1: POR default — chain passthrough
        // =====================================================================
        $display("\n[1] POR default: chain passthrough (sel_local=0)");
        do_por;

        chain_side_gpio_out = 15'h5A5A;
        chain_side_gpio_oeb = 15'h3333;
        local_proj_gpio_out = 15'h1234;
        local_proj_gpio_oeb = 15'h0F0F;
        #10;

        assert_eq_vec(pad_side_gpio_out, 15'h5A5A, "pad_out = chain_out (sel=0)");
        assert_eq_vec(pad_side_gpio_oeb, 15'h3333, "pad_oeb = chain_oeb (sel=0)");

        // =====================================================================
        // Test 2: Inbound broadcast
        // =====================================================================
        $display("[2] Inbound broadcast: pad_in -> local + chain");
        pad_side_gpio_in = 15'h7FFF;
        #10;
        assert_eq_vec(local_proj_gpio_in, 15'h7FFF, "local_in = pad_in");
        assert_eq_vec(chain_side_gpio_in, 15'h7FFF, "chain_in = pad_in");

        // =====================================================================
        // Test 3: Select local project
        // =====================================================================
        $display("[3] Select local project (sel_local=1)");
        shift_bit(1'b1);
        pulse_latch;
        #10;

        assert_eq_vec(pad_side_gpio_out, 15'h1234, "pad_out = local_out (sel=1)");
        assert_eq_vec(pad_side_gpio_oeb, 15'h0F0F, "pad_oeb = local_oeb (sel=1)");

        // =====================================================================
        // Test 4: MUX switching: toggle sel
        // =====================================================================
        $display("[4] MUX switching on sel toggle");
        shift_bit(1'b0);
        pulse_latch;
        #10;

        assert_eq_vec(pad_side_gpio_out, 15'h5A5A, "pad_out = chain_out after desel");
        assert_eq_vec(pad_side_gpio_oeb, 15'h3333, "pad_oeb = chain_oeb after desel");

        // =====================================================================
        // Test 5: DM bus MUX
        // =====================================================================
        $display("[5] DM bus MUX");
        chain_side_gpio_dm = 45'h1AAAAAAAAA;
        local_proj_gpio_dm = 45'h155555555;
        #10;

        assert_eq_vec(pad_side_gpio_dm[44:0], 45'h1AAAAAAAAA, "pad_dm = chain_dm (sel=0)");

        shift_bit(1'b1);
        pulse_latch;
        #10;
        assert_eq_vec(pad_side_gpio_dm[44:0], 45'h155555555, "pad_dm = local_dm (sel=1)");

        // =====================================================================
        // Test 6: Scan chain feedthrough on output side
        // =====================================================================
        $display("[6] Scan chain feedthrough");
        scan_latch = 1'b1;
        #1;
        assert_eq(scan_latch_out_e, 1, "scan_latch_out_e passthrough");
        scan_latch = 1'b0;
        #1;

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
