// SPDX-License-Identifier: Apache-2.0
// tb_scan_chain — Full 57-bit scan chain connectivity test
//
// Verifies the complete scan chain through the wrapper:
//   Scan Ctrl -> Purple Left (3b) -> Purple Top (3b) -> Purple Right (3b)
//   -> Grid top-down serpentine (48b) -> Scan Ctrl dout
//
// Key insight: when pulse_latch fires, the chain gets one extra clock
// (the controller relocks on the posedge but the ICG still passes that
// clock since latch_en was sampled during the prior low phase). This
// means shift_regs are "dirty" after latch — shifted by 1 with scan_din
// from the last shift bit entering position 0. The SHADOW registers
// correctly capture the pre-shift values.
//
// Therefore: readback tests work by loading + immediately reading back
// (without latch), while configuration tests verify shadow_regs via
// hierarchy probes after latch.

`timescale 1ns/1ps
`default_nettype none

module tb_scan_chain;

    integer error_count;
    reg scan_clk, scan_din, scan_latch;
    reg por_n, sys_rst_n;

    `include "../common/scan_tasks.vh"

    localparam ROWS = 4;
    localparam COLS = 3;
    localparam [7:0] MAGIC_WORD = 8'hA5;
    localparam TOTAL_SCAN_BITS = 3 + 3 + 3 + ROWS * COLS * 4; // 57

    // DUT signals
    reg  sys_clk;
    wire [43:0] gpio_in;
    wire [43:0] gpio_out, gpio_oeb, gpio_inp_dis;
    wire [43:0] gpio_ib_mode_sel, gpio_vtrip_sel, gpio_slow_sel, gpio_holdover;
    wire [43:0] gpio_analog_en, gpio_analog_sel, gpio_analog_pol;
    wire [43:0] gpio_dm2, gpio_dm1, gpio_dm0;
    wire [43:0] gpio_loopback_one  = {44{1'b1}};
    wire [43:0] gpio_loopback_zero = {44{1'b0}};

    assign gpio_in[37:0] = 38'b0;
    assign gpio_in[38]   = sys_clk;
    assign gpio_in[39]   = sys_rst_n;
    assign gpio_in[40]   = scan_clk;
    assign gpio_in[41]   = scan_din;
    assign gpio_in[42]   = scan_latch;
    assign gpio_in[43]   = 1'b0;

    openframe_project_wrapper #(
        .ROWS(ROWS), .COLS(COLS), .MAGIC_WORD(MAGIC_WORD)
    ) dut (
        .porb_h(por_n), .porb_l(por_n), .por_l(~por_n),
        .resetb_h(sys_rst_n), .resetb_l(sys_rst_n),
        .mask_rev(32'h0),
        .gpio_in(gpio_in), .gpio_in_h(gpio_in),
        .gpio_out(gpio_out), .gpio_oeb(gpio_oeb),
        .gpio_inp_dis(gpio_inp_dis),
        .gpio_ib_mode_sel(gpio_ib_mode_sel),
        .gpio_vtrip_sel(gpio_vtrip_sel),
        .gpio_slow_sel(gpio_slow_sel),
        .gpio_holdover(gpio_holdover),
        .gpio_analog_en(gpio_analog_en),
        .gpio_analog_sel(gpio_analog_sel),
        .gpio_analog_pol(gpio_analog_pol),
        .gpio_dm2(gpio_dm2), .gpio_dm1(gpio_dm1), .gpio_dm0(gpio_dm0),
        .analog_io(), .analog_noesd_io(),
        .gpio_loopback_one(gpio_loopback_one),
        .gpio_loopback_zero(gpio_loopback_zero)
    );

    wire scan_dout = gpio_out[43];

    // Clocks
    initial sys_clk = 0;
    always #5 sys_clk = ~sys_clk;
    initial scan_clk = 0;
    always #50 scan_clk = ~scan_clk;

    // ---------------------------------------------------------------
    // Capture task: reads scan_dout BEFORE the clock edge (pre-shift value)
    // then clocks the chain. This gives us the true pipeline output.
    // ---------------------------------------------------------------
    task shift_bit_capture;
        input bit_val;
        output bit_out;
        begin
            bit_out = scan_dout;   // capture BEFORE the shift
            scan_din = bit_val;
            @(posedge scan_clk);
            #1;
        end
    endtask

    // Shift N bits into chain, simultaneously capturing N bits of readback.
    // After this task, the chain contains the new pattern and captured[]
    // holds what was previously in the chain.
    task shift_and_capture;
        input integer n;
        input [255:0] pattern;
        output [255:0] captured;
        integer i;
        reg bit_out;
        begin
            captured = 256'b0;
            for (i = n - 1; i >= 0; i = i - 1) begin
                shift_bit_capture(pattern[i], bit_out);
                captured[i] = bit_out;
            end
        end
    endtask

    integer i;
    reg [255:0] captured;

    initial begin
        $dumpfile("tb_scan_chain.vcd");
        $dumpvars(0, tb_scan_chain);

        error_count = 0;

        // =====================================================================
        // Test 1: Shift all-ones, then readback by shifting zeros through
        // =====================================================================
        $display("\n[1] Shift all-ones + immediate readback");
        do_por;

        // Unlock and shift 57 ones into the chain (first pass — fills chain
        // with ones, readback is undefined since shift_regs had no reset)
        shift_magic(MAGIC_WORD);
        shift_n_bits(TOTAL_SCAN_BITS, {256{1'b1}});

        // Now the chain has all-ones. The controller is still unlocked (no
        // latch yet). Shift zeros through and read back the ones.
        shift_and_capture(TOTAL_SCAN_BITS, {256{1'b0}}, captured);

        begin : check_allones
            integer ones_count;
            ones_count = 0;
            for (i = 0; i < TOTAL_SCAN_BITS; i = i + 1)
                if (captured[i] === 1'b1) ones_count = ones_count + 1;
            if (ones_count !== TOTAL_SCAN_BITS) begin
                $display("  FAIL: expected %0d ones, got %0d", TOTAL_SCAN_BITS, ones_count);
                error_count = error_count + 1;
            end else begin
                $display("  PASS: all %0d bits read back as 1", TOTAL_SCAN_BITS);
            end
        end

        // Latch to re-lock (shift_regs will be dirty but we don't care)
        scan_din = 1'b0;
        pulse_latch;
        #100;

        // =====================================================================
        // Test 2: Walking-one pattern (no latch — direct readback)
        // =====================================================================
        $display("\n[2] Walking-one pattern");
        begin : walk_one_block
            reg [255:0] walk_pattern;
            integer bit_pos, errs_before;
            errs_before = error_count;

            for (bit_pos = 0; bit_pos < TOTAL_SCAN_BITS; bit_pos = bit_pos + 1) begin
                // Reset chain to known state
                do_por;
                shift_magic(MAGIC_WORD);

                // Fill chain with zeros first (clears undefined shift_regs)
                shift_n_bits(TOTAL_SCAN_BITS, 256'b0);

                // Now shift the walking-one pattern in
                walk_pattern = 256'b0;
                walk_pattern[bit_pos] = 1'b1;
                shift_n_bits(TOTAL_SCAN_BITS, walk_pattern);

                // Immediately read back by shifting zeros (no latch)
                shift_and_capture(TOTAL_SCAN_BITS, 256'b0, captured);

                // Check that only bit_pos is set
                for (i = 0; i < TOTAL_SCAN_BITS; i = i + 1) begin
                    if (i == bit_pos) begin
                        if (captured[i] !== 1'b1) begin
                            $display("  FAIL: walk[%0d] bit %0d should be 1, got %b",
                                     bit_pos, i, captured[i]);
                            error_count = error_count + 1;
                        end
                    end else begin
                        if (captured[i] !== 1'b0) begin
                            $display("  FAIL: walk[%0d] bit %0d should be 0, got %b",
                                     bit_pos, i, captured[i]);
                            error_count = error_count + 1;
                        end
                    end
                end
            end

            if (error_count == errs_before)
                $display("  PASS: all %0d walking-one positions verified", TOTAL_SCAN_BITS);
        end

        // =====================================================================
        // Test 3: Verify serpentine order via hierarchy probes (after latch)
        // =====================================================================
        $display("\n[3] Verify scan chain ordering via hierarchy probes");
        begin : order_block
            integer errs_before;
            errs_before = error_count;

            do_por;
            shift_magic(MAGIC_WORD);

            // Build alternating pattern: bit[i] = i % 2
            begin : shift_alt
                reg [255:0] alt_pattern;
                alt_pattern = 256'b0;
                for (i = 0; i < TOTAL_SCAN_BITS; i = i + 1)
                    alt_pattern[i] = i[0];
                shift_n_bits(TOTAL_SCAN_BITS, alt_pattern);
            end

            // Latch to capture into shadow_regs
            scan_din = 1'b0;
            pulse_latch;
            #100;

            // Check shadow_regs (ctrl_out) via hierarchy probes
            // Purple Left (positions 0,1,2): bits {bit2, bit1, bit0}
            // bit0=0, bit1=1, bit2=0 -> shadow_reg = 3'b010
            assert_eq_vec(dut.u_purple_left.u_node.shadow_reg,
                         3'b010, "Purple Left shadow = {bit2,bit1,bit0} = 010");

            // Purple Top (positions 3,4,5): bit3=1, bit4=0, bit5=1
            // shadow_reg = {bit5, bit4, bit3} = 3'b101
            assert_eq_vec(dut.u_purple_top.u_node.shadow_reg,
                         3'b101, "Purple Top shadow = {bit5,bit4,bit3} = 101");

            // Purple Right (positions 6,7,8): bit6=0, bit7=1, bit8=0
            // shadow_reg = {bit8, bit7, bit6} = 3'b010
            assert_eq_vec(dut.u_purple_right.u_node.shadow_reg,
                         3'b010, "Purple Right shadow = {bit8,bit7,bit6} = 010");

            // Grid serpentine: Row 3 R->L, Row 2 L->R, Row 1 R->L, Row 0 L->R
            // First grid cell: cell(3,2) at PROJ_IDX=0, green at position 9
            // bit9 = 9[0] = 1
            assert_eq(dut.gen_row[3].gen_col[2].u_green.u_node.shadow_reg, 1,
                      "green(3,2) = bit9 = 1");

            // cell(3,1) at PROJ_IDX=1, green at position 13
            // bit13 = 13[0] = 1
            assert_eq(dut.gen_row[3].gen_col[1].u_green.u_node.shadow_reg, 1,
                      "green(3,1) = bit13 = 1");

            // cell(2,0) at PROJ_IDX=3, green at position 21
            // bit21 = 21[0] = 1
            assert_eq(dut.gen_row[2].gen_col[0].u_green.u_node.shadow_reg, 1,
                      "green(2,0) = bit21 = 1");

            // Last grid cell: cell(0,2) at PROJ_IDX=11, green at position 53
            // bit53 = 53[0] = 1
            assert_eq(dut.gen_row[0].gen_col[2].u_green.u_node.shadow_reg, 1,
                      "green(0,2) = bit53 = 1");

            // Last position: top_orange(0,2) at position 56
            // bit56 = 56[0] = 0
            assert_eq(dut.gen_row[0].gen_col[2].u_top_orange.u_node.shadow_reg, 0,
                      "top_orange(0,2) = bit56 = 0");

            if (error_count == errs_before)
                $display("  PASS: scan chain order verified via shadow_regs");
        end

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
        #10_000_000;
        $display("ERROR: Timeout!");
        $finish;
    end

endmodule
