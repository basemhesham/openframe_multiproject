// SPDX-License-Identifier: Apache-2.0
// tb_scan_ctrl — Unit test for scan_controller_macro
//
// Tests: locked power-on, wrong magic, correct magic unlock, clock/latch
// gating, auto re-lock on latch, re-unlock, sys_reset_n, readback path.

`timescale 1ns/1ps
`default_nettype none

module tb_scan_ctrl;

    integer error_count;
    reg scan_clk, scan_din, scan_latch;
    reg por_n, sys_rst_n;

    `include "../common/scan_tasks.vh"

    // DUT signals
    wire chain_scan_clk, chain_scan_din, chain_scan_latch;
    reg  chain_scan_dout_src;
    wire pad_scan_dout;

    scan_controller_macro #(.MAGIC_WORD(8'hA5)) u_ctrl (
        .por_n           (por_n),
        .sys_reset_n     (sys_rst_n),
        .pad_scan_clk    (scan_clk),
        .pad_scan_din    (scan_din),
        .pad_scan_latch  (scan_latch),
        .pad_scan_dout   (pad_scan_dout),
        .chain_scan_clk  (chain_scan_clk),
        .chain_scan_din  (chain_scan_din),
        .chain_scan_latch(chain_scan_latch),
        .chain_scan_dout (chain_scan_dout_src)
    );

    // Clocks
    initial scan_clk = 0;
    always #50 scan_clk = ~scan_clk;

    initial begin
        $dumpfile("tb_scan_ctrl.vcd");
        $dumpvars(0, tb_scan_ctrl);

        error_count = 0;
        chain_scan_dout_src = 1'b0;

        // =====================================================================
        // Test 1: Power-on locked state
        // =====================================================================
        $display("\n[1] Power-on locked state");
        do_por;
        assert_eq(u_ctrl.unlocked, 0, "unlocked=0 after POR");
        assert_eq_vec(u_ctrl.magic_sr, 8'h00, "magic_sr=0 after POR");

        // =====================================================================
        // Test 2: Wrong magic word — stays locked
        // =====================================================================
        $display("[2] Wrong magic word (0xFF)");
        shift_magic(8'hFF);
        assert_eq(u_ctrl.unlocked, 0, "unlocked=0 after wrong magic");

        // =====================================================================
        // Test 3: Correct magic word — unlocks
        // =====================================================================
        $display("[3] Correct magic word (0xA5)");
        do_por;
        shift_magic(8'hA5);
        assert_eq(u_ctrl.unlocked, 1, "unlocked=1 after correct magic");

        // =====================================================================
        // Test 4: Chain clock passes when unlocked
        // =====================================================================
        $display("[4] Chain clock passes when unlocked");
        // After unlock, chain_scan_clk should follow scan_clk (through ICG)
        // Wait for next rising edge
        @(negedge scan_clk);  // ICG latches GATE on low phase
        #1;
        @(posedge scan_clk);
        #1;
        // chain_scan_clk should be high now (GCLK = CLK & latch_en)
        // Since unlocked=1 and CLK just went high, GCLK should be 1
        // Note: ICG latch captures on low CLK, so after posedge it should be high
        assert_eq(chain_scan_clk, 1, "chain_scan_clk passes when unlocked");

        // =====================================================================
        // Test 5: Chain data passthrough when unlocked
        // =====================================================================
        $display("[5] Chain data passthrough");
        scan_din = 1'b1;
        #1;
        assert_eq(chain_scan_din, 1, "chain_scan_din = pad_scan_din = 1");
        scan_din = 1'b0;
        #1;
        assert_eq(chain_scan_din, 0, "chain_scan_din = pad_scan_din = 0");

        // =====================================================================
        // Test 6: Latch gating when locked
        // =====================================================================
        $display("[6] Latch blocked when locked");
        do_por; // re-lock
        scan_latch = 1'b1;
        #1;
        assert_eq(chain_scan_latch, 0, "chain_scan_latch=0 when locked");
        scan_latch = 1'b0;
        #1;

        // =====================================================================
        // Test 7: Latch passes when unlocked
        // =====================================================================
        $display("[7] Latch passes when unlocked");
        shift_magic(8'hA5);
        scan_latch = 1'b1;
        #1;
        assert_eq(chain_scan_latch, 1, "chain_scan_latch=1 when unlocked+latch");

        // =====================================================================
        // Test 8: Auto re-lock on latch assertion
        // =====================================================================
        $display("[8] Auto re-lock on latch");
        // Latch is still high from test 7, wait for posedge scan_clk
        @(posedge scan_clk);
        #1;
        // Controller should see pad_scan_latch=1 and re-lock
        assert_eq(u_ctrl.unlocked, 0, "unlocked=0 after latch re-lock");
        assert_eq_vec(u_ctrl.magic_sr, 8'h00, "magic_sr cleared on re-lock");
        scan_latch = 1'b0;
        #10;

        // =====================================================================
        // Test 9: Re-unlock after re-lock
        // =====================================================================
        $display("[9] Re-unlock after re-lock");
        shift_magic(8'hA5);
        assert_eq(u_ctrl.unlocked, 1, "unlocked=1 after re-unlock");

        // Clean up for next test
        scan_latch = 1'b1;
        @(posedge scan_clk); #1;
        scan_latch = 1'b0;
        @(posedge scan_clk); #1;

        // =====================================================================
        // Test 10: sys_reset_n resets controller
        // =====================================================================
        $display("[10] sys_reset_n resets controller");
        shift_magic(8'hA5);
        assert_eq(u_ctrl.unlocked, 1, "unlocked=1 before sys_reset");
        sys_rst_n = 1'b0;
        @(posedge scan_clk); #1;
        assert_eq(u_ctrl.unlocked, 0, "unlocked=0 after sys_reset_n=0");
        sys_rst_n = 1'b1;
        #50;

        // =====================================================================
        // Test 11: Readback path always connected
        // =====================================================================
        $display("[11] Readback path always connected");
        // Even when locked, chain_scan_dout -> pad_scan_dout
        chain_scan_dout_src = 1'b1;
        #1;
        assert_eq(pad_scan_dout, 1, "readback: dout=1");
        chain_scan_dout_src = 1'b0;
        #1;
        assert_eq(pad_scan_dout, 0, "readback: dout=0");

        // =====================================================================
        // Test 12: Partial magic word doesn't unlock
        // =====================================================================
        $display("[12] Partial magic word");
        do_por;
        // 0xA5 = 1010_0101. Shift first 7 correct bits then 1 wrong bit.
        shift_bit(1'b1); // bit 7
        shift_bit(1'b0); // bit 6
        shift_bit(1'b1); // bit 5
        shift_bit(1'b0); // bit 4
        shift_bit(1'b0); // bit 3
        shift_bit(1'b1); // bit 2
        shift_bit(1'b0); // bit 1
        shift_bit(1'b0); // bit 0 — WRONG (should be 1)
        assert_eq(u_ctrl.unlocked, 0, "partial magic doesn't unlock");

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
