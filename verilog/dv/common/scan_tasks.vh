// SPDX-License-Identifier: Apache-2.0
// scan_tasks.vh — Shared tasks for scan chain testbenches
//
// Include this file inside any testbench that drives the scan chain.
// Requires the following regs/wires to be defined in the including module:
//   reg scan_clk, scan_din, scan_latch;
//   integer error_count;

// ---------------------------------------------------------------
// shift_bit — Shift one bit into the scan chain
// ---------------------------------------------------------------
task shift_bit;
    input bit_val;
    begin
        scan_din = bit_val;
        @(posedge scan_clk);
        #1;
    end
endtask

// ---------------------------------------------------------------
// shift_magic — Shift 8-bit magic word MSB first
// ---------------------------------------------------------------
task shift_magic;
    input [7:0] word;
    integer i;
    begin
        for (i = 7; i >= 0; i = i - 1)
            shift_bit(word[i]);
    end
endtask

// ---------------------------------------------------------------
// shift_n_bits — Shift N bits from a wide register, MSB first
// ---------------------------------------------------------------
task shift_n_bits;
    input integer n;
    input [255:0] pattern;
    integer i;
    begin
        for (i = n - 1; i >= 0; i = i - 1)
            shift_bit(pattern[i]);
    end
endtask

// ---------------------------------------------------------------
// pulse_latch — Assert scan_latch for one scan_clk cycle
// ---------------------------------------------------------------
task pulse_latch;
    begin
        scan_latch = 1'b1;
        @(posedge scan_clk);
        #1;
        scan_latch = 1'b0;
        @(posedge scan_clk);
        #1;
    end
endtask

// ---------------------------------------------------------------
// assert_eq — Self-checking assertion with error counter
// ---------------------------------------------------------------
task assert_eq;
    input integer actual;
    input integer expected;
    input [255:0] msg; // use reg for string-like storage
    begin
        if (actual !== expected) begin
            $display("  FAIL: %0s — got %0d, expected %0d", msg, actual, expected);
            error_count = error_count + 1;
        end
    end
endtask

// ---------------------------------------------------------------
// assert_eq_vec — Assert for multi-bit vectors (up to 64 bits)
// ---------------------------------------------------------------
task assert_eq_vec;
    input [63:0] actual;
    input [63:0] expected;
    input [255:0] msg;
    begin
        if (actual !== expected) begin
            $display("  FAIL: %0s — got 0x%0h, expected 0x%0h", msg, actual, expected);
            error_count = error_count + 1;
        end
    end
endtask

// ---------------------------------------------------------------
// do_por — Drive power-on reset sequence
// Requires: por_n, sys_rst_n defined in including module
// ---------------------------------------------------------------
task do_por;
    begin
        por_n = 1'b0;
        sys_rst_n = 1'b0;
        scan_din = 1'b0;
        scan_latch = 1'b0;
        #200;
        por_n = 1'b1;
        #50;
        sys_rst_n = 1'b1;
        #50;
    end
endtask
