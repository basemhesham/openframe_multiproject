// SPDX-License-Identifier: Apache-2.0
// tb_project_select — Integration test for project enable/disable
//
// Verifies: single project enable, all enable, none enable,
// clock gating, config survives sys_reset_n.

`timescale 1ns/1ps
`default_nettype none

module tb_project_select;

    integer error_count;
    reg scan_clk, scan_din, scan_latch;
    reg por_n, sys_rst_n;

    `include "../common/scan_tasks.vh"

    localparam ROWS = 4;
    localparam COLS = 3;
    localparam [7:0] MAGIC_WORD = 8'hA5;
    localparam TOTAL_SCAN_BITS = 57;
    localparam SC_GRID_BASE = 9; // After 9 purple bits

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

    // Clocks
    initial sys_clk = 0;
    always #5 sys_clk = ~sys_clk;
    initial scan_clk = 0;
    always #50 scan_clk = ~scan_clk;

    // ---------------------------------------------------------------
    // Helper: Build 57-bit config vector for a single project enable
    // Serpentine mapping: row_from_top = ROWS-1-r, then within that row
    //   even row_from_top -> R-to-L (SERP_C = COLS-1-c)
    //   odd row_from_top  -> L-to-R (SERP_C = c)
    // Grid bit position for green at (r,c):
    //   PROJ_IDX = row_from_top * COLS + SERP_C
    //   green_bit = SC_GRID_BASE + PROJ_IDX * 4  (green is node 0 in cell)
    // ---------------------------------------------------------------
    function [255:0] make_config;
        input integer target_r;
        input integer target_c;
        input         enable_purples; // set all purple master_en bits
        integer row_from_top, serp_c, proj_idx, green_bit;
        begin
            make_config = 256'b0;

            // Purple master enable bits (first bit shifted = MSB of scan_ctrl)
            // Purple Left (positions 0-2): master_en at scan_ctrl[2] = position 2
            // Purple Top (positions 3-5): master_en at position 5
            // Purple Right (positions 6-8): master_en at position 8
            if (enable_purples) begin
                make_config[2] = 1'b1; // Purple Left master_en
                make_config[5] = 1'b1; // Purple Top master_en
                make_config[8] = 1'b1; // Purple Right master_en
            end

            // Green enable bit for target project
            if (target_r >= 0 && target_c >= 0) begin
                row_from_top = ROWS - 1 - target_r;
                if (row_from_top % 2 == 0)
                    serp_c = COLS - 1 - target_c;
                else
                    serp_c = target_c;
                proj_idx = row_from_top * COLS + serp_c;
                green_bit = SC_GRID_BASE + proj_idx * 4; // green is node 0
                make_config[green_bit] = 1'b1;
            end
        end
    endfunction

    // Helper: configure the chain with a given 57-bit vector
    task configure;
        input [255:0] config_vec;
        begin
            shift_magic(MAGIC_WORD);
            shift_n_bits(TOTAL_SCAN_BITS, config_vec);
            pulse_latch;
            #200; // Let ICG settle
        end
    endtask

    // Helper: check proj_en for a specific cell
    // Cannot use a function/task with variable hierarchy paths in Verilog,
    // so we'll check specific cells inline.

    integer r, c;

    initial begin
        $dumpfile("tb_project_select.vcd");
        $dumpvars(0, tb_project_select);

        error_count = 0;

        // =====================================================================
        // Test 1: Enable single project (0,0) — bottom-left
        // =====================================================================
        $display("\n[1] Enable single project (0,0)");
        do_por;
        configure(make_config(0, 0, 1));

        // Check project (0,0) is enabled
        assert_eq(dut.gen_row[0].gen_col[0].u_green.u_node.shadow_reg, 1,
                  "proj_en(0,0)=1");
        // Check a few others are disabled
        assert_eq(dut.gen_row[0].gen_col[1].u_green.u_node.shadow_reg, 0,
                  "proj_en(0,1)=0");
        assert_eq(dut.gen_row[1].gen_col[0].u_green.u_node.shadow_reg, 0,
                  "proj_en(1,0)=0");
        assert_eq(dut.gen_row[3].gen_col[2].u_green.u_node.shadow_reg, 0,
                  "proj_en(3,2)=0");

        // =====================================================================
        // Test 2: Enable single project (3,2) — top-right
        // =====================================================================
        $display("\n[2] Enable single project (3,2)");
        do_por;
        configure(make_config(3, 2, 1));

        assert_eq(dut.gen_row[3].gen_col[2].u_green.u_node.shadow_reg, 1,
                  "proj_en(3,2)=1");
        assert_eq(dut.gen_row[0].gen_col[0].u_green.u_node.shadow_reg, 0,
                  "proj_en(0,0)=0");

        // =====================================================================
        // Test 3: Enable all projects
        // =====================================================================
        $display("\n[3] Enable all 12 projects");
        do_por;
        begin : enable_all_block
            reg [255:0] all_config;
            integer row_from_top, serp_c, proj_idx, green_bit;
            all_config = 256'b0;
            // Set all purple master_en
            all_config[2] = 1'b1;
            all_config[5] = 1'b1;
            all_config[8] = 1'b1;
            // Set all green bits
            for (r = 0; r < ROWS; r = r + 1) begin
                for (c = 0; c < COLS; c = c + 1) begin
                    row_from_top = ROWS - 1 - r;
                    if (row_from_top % 2 == 0)
                        serp_c = COLS - 1 - c;
                    else
                        serp_c = c;
                    proj_idx = row_from_top * COLS + serp_c;
                    green_bit = SC_GRID_BASE + proj_idx * 4;
                    all_config[green_bit] = 1'b1;
                end
            end
            configure(all_config);
        end

        // Check all enabled
        assert_eq(dut.gen_row[0].gen_col[0].u_green.u_node.shadow_reg, 1, "all: (0,0)=1");
        assert_eq(dut.gen_row[0].gen_col[1].u_green.u_node.shadow_reg, 1, "all: (0,1)=1");
        assert_eq(dut.gen_row[0].gen_col[2].u_green.u_node.shadow_reg, 1, "all: (0,2)=1");
        assert_eq(dut.gen_row[1].gen_col[0].u_green.u_node.shadow_reg, 1, "all: (1,0)=1");
        assert_eq(dut.gen_row[2].gen_col[1].u_green.u_node.shadow_reg, 1, "all: (2,1)=1");
        assert_eq(dut.gen_row[3].gen_col[2].u_green.u_node.shadow_reg, 1, "all: (3,2)=1");

        // =====================================================================
        // Test 4: No projects enabled (all zeros except purples)
        // =====================================================================
        $display("\n[4] No projects enabled");
        do_por;
        begin : none_block
            reg [255:0] none_config;
            none_config = 256'b0;
            configure(none_config);
        end

        assert_eq(dut.gen_row[0].gen_col[0].u_green.u_node.shadow_reg, 0, "none: (0,0)=0");
        assert_eq(dut.gen_row[3].gen_col[2].u_green.u_node.shadow_reg, 0, "none: (3,2)=0");

        // =====================================================================
        // Test 5: Clock gating — only enabled project toggles
        // =====================================================================
        $display("\n[5] Clock gating verification");
        do_por;
        configure(make_config(1, 1, 1));

        // Count edges on project (1,1) — should have some
        begin : clk_check
            integer edges_11, edges_00;
            edges_11 = 0;
            edges_00 = 0;
            // Sample over 20 sys_clk cycles
            repeat (40) begin
                @(posedge sys_clk);
                #1;
            end
            // We can't easily count edges from here. Instead, check the ICG output.
            // proj_clk should only toggle for enabled project.
            // Since proj_en(1,1)=1 and ICG gates on it, proj_clk(1,1) should be active.
            // The ICG behavioral model: GCLK = CLK & latch_en, where latch_en latches GATE on low CLK.
            // So when GATE=1 and CLK goes high, GCLK goes high.

            // Check that proj_clk(1,1) has been toggling by verifying it's not stuck.
            // Wait for a posedge sys_clk and check proj_clk.
            @(negedge sys_clk); #1;
            @(posedge sys_clk); #1;
            assert_eq(dut.gen_row[1].gen_col[1].proj_clk, 1,
                      "proj_clk(1,1) high on sys_clk posedge");

            @(negedge sys_clk); #1;
            assert_eq(dut.gen_row[1].gen_col[1].proj_clk, 0,
                      "proj_clk(1,1) low on sys_clk negedge");

            // Check disabled project's clock is gated
            @(posedge sys_clk); #1;
            assert_eq(dut.gen_row[0].gen_col[0].proj_clk, 0,
                      "proj_clk(0,0) gated (disabled)");
        end

        // =====================================================================
        // Test 6: Config survives sys_reset_n
        // =====================================================================
        $display("\n[6] Config survives sys_reset_n");
        // Currently project (1,1) is enabled. Assert sys_reset_n.
        sys_rst_n = 1'b0;
        #200;
        sys_rst_n = 1'b1;
        #200;

        // proj_en should still be 1 (shadow_reg reset by POR only)
        assert_eq(dut.gen_row[1].gen_col[1].u_green.u_node.shadow_reg, 1,
                  "proj_en(1,1) survives sys_reset_n");

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
        #5_000_000;
        $display("ERROR: Timeout!");
        $finish;
    end

endmodule
