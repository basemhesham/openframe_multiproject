// SPDX-License-Identifier: Apache-2.0
// tb_reset_behavior — Integration test for POR vs sys_reset_n semantics
//
// Verifies:
//   - POR clears all shadow regs + scan controller
//   - sys_reset_n resets scan controller but NOT shadow regs
//   - proj_reset_n tracks sys_reset_n when enabled

`timescale 1ns/1ps
`default_nettype none

module tb_reset_behavior;

    integer error_count;
    reg scan_clk, scan_din, scan_latch;
    reg por_n, sys_rst_n;

    `include "../common/scan_tasks.vh"

    localparam ROWS = 4;
    localparam COLS = 3;
    localparam [7:0] MAGIC_WORD = 8'hA5;
    localparam TOTAL_SCAN_BITS = 57;
    localparam SC_GRID_BASE = 9;

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

    initial sys_clk = 0;
    always #5 sys_clk = ~sys_clk;
    initial scan_clk = 0;
    always #50 scan_clk = ~scan_clk;

    // Helper: compute green bit position for cell (r,c)
    function integer get_green_bit;
        input integer r, c;
        integer row_from_top, serp_c, proj_idx;
        begin
            row_from_top = ROWS - 1 - r;
            if (row_from_top % 2 == 0) serp_c = COLS - 1 - c;
            else serp_c = c;
            proj_idx = row_from_top * COLS + serp_c;
            get_green_bit = SC_GRID_BASE + proj_idx * 4;
        end
    endfunction

    task configure_project;
        input integer r, c;
        reg [255:0] config_vec;
        begin
            config_vec = 256'b0;
            config_vec[get_green_bit(r, c)] = 1'b1;
            config_vec[2] = 1'b1; // Purple Left master_en
            config_vec[5] = 1'b1; // Purple Top master_en
            config_vec[8] = 1'b1; // Purple Right master_en
            shift_magic(MAGIC_WORD);
            shift_n_bits(TOTAL_SCAN_BITS, config_vec);
            pulse_latch;
            #200;
        end
    endtask

    initial begin
        $dumpfile("tb_reset_behavior.vcd");
        $dumpvars(0, tb_reset_behavior);

        error_count = 0;

        // =====================================================================
        // Test 1: POR clears all shadow regs
        // =====================================================================
        $display("\n[1] POR clears all shadow regs");
        // First configure something, then POR
        do_por;
        configure_project(2, 1);

        // Verify project (2,1) is enabled
        assert_eq(dut.gen_row[2].gen_col[1].u_green.u_node.shadow_reg, 1,
                  "before POR: proj_en(2,1)=1");

        // Now POR
        por_n = 1'b0;
        #200;
        por_n = 1'b1;
        #100;

        // All shadow regs should be 0
        assert_eq(dut.gen_row[2].gen_col[1].u_green.u_node.shadow_reg, 0,
                  "after POR: proj_en(2,1)=0");
        assert_eq(dut.gen_row[0].gen_col[0].u_green.u_node.shadow_reg, 0,
                  "after POR: proj_en(0,0)=0");

        // =====================================================================
        // Test 2: POR clears scan controller
        // =====================================================================
        $display("\n[2] POR clears scan controller");
        assert_eq(dut.u_scan_ctrl.unlocked, 0, "after POR: unlocked=0");
        assert_eq_vec(dut.u_scan_ctrl.magic_sr, 8'h00, "after POR: magic_sr=0");

        // =====================================================================
        // Test 3: sys_reset_n does NOT clear shadow regs
        // =====================================================================
        $display("\n[3] sys_reset_n does NOT clear shadow regs");
        sys_rst_n = 1'b1;
        #100;
        configure_project(1, 0);

        assert_eq(dut.gen_row[1].gen_col[0].u_green.u_node.shadow_reg, 1,
                  "before sys_reset: proj_en(1,0)=1");

        // Assert sys_reset_n
        sys_rst_n = 1'b0;
        #200;
        sys_rst_n = 1'b1;
        #100;

        // Shadow reg should STILL be 1
        assert_eq(dut.gen_row[1].gen_col[0].u_green.u_node.shadow_reg, 1,
                  "after sys_reset: proj_en(1,0) STILL=1");

        // =====================================================================
        // Test 4: sys_reset_n resets scan controller
        // =====================================================================
        $display("\n[4] sys_reset_n resets scan controller");
        // Unlock the controller
        shift_magic(MAGIC_WORD);
        assert_eq(dut.u_scan_ctrl.unlocked, 1, "before sys_reset: unlocked=1");

        // sys_reset_n
        sys_rst_n = 1'b0;
        @(posedge scan_clk); #1;
        assert_eq(dut.u_scan_ctrl.unlocked, 0, "after sys_reset: unlocked=0");
        sys_rst_n = 1'b1;
        #100;

        // =====================================================================
        // Test 5: proj_reset_n tracks sys_reset_n when enabled
        // =====================================================================
        $display("\n[5] proj_reset_n tracks sys_reset_n when enabled");
        do_por;
        configure_project(0, 0);

        // proj_en(0,0)=1, sys_reset_n=1 -> proj_reset_n=1
        #100;
        assert_eq(dut.gen_row[0].gen_col[0].proj_rst_n, 1,
                  "proj_reset_n=1 when enabled+rst=1");

        // Assert sys_reset_n -> proj_reset_n should go to 0
        sys_rst_n = 1'b0;
        #10;
        assert_eq(dut.gen_row[0].gen_col[0].proj_rst_n, 0,
                  "proj_reset_n=0 when enabled+rst=0");

        sys_rst_n = 1'b1;
        #10;
        assert_eq(dut.gen_row[0].gen_col[0].proj_rst_n, 1,
                  "proj_reset_n=1 when enabled+rst=1 (restored)");

        // =====================================================================
        // Test 6: POR during active operation clears everything
        // =====================================================================
        $display("\n[6] POR during active operation");
        do_por;
        configure_project(3, 1);

        assert_eq(dut.gen_row[3].gen_col[1].u_green.u_node.shadow_reg, 1,
                  "before mid-POR: proj_en(3,1)=1");

        // POR while clock is running
        por_n = 1'b0;
        #50;
        por_n = 1'b1;
        #100;

        assert_eq(dut.gen_row[3].gen_col[1].u_green.u_node.shadow_reg, 0,
                  "after mid-POR: proj_en(3,1)=0");
        assert_eq(dut.u_scan_ctrl.unlocked, 0, "after mid-POR: unlocked=0");

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
