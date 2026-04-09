// SPDX-License-Identifier: Apache-2.0
// scan_controller_macro — Security gate for the scan chain
//
// Locked on reset (POR or sys_reset_n). External controller shifts in
// magic word (0xA5) to unlock. Chain immediately re-locks on latch assertion
// (when shadow registers capture). One-shot: must re-unlock for every
// reconfiguration.
//
// Protocol:
//   1. Reset (POR/sys_reset_n) -> LOCKED
//   2. Shift in MAGIC_WORD on pad_scan_din -> UNLOCKED
//   3. Shift in all configuration bits
//   4. Assert pad_scan_latch -> shadow regs capture, chain LOCKS
//   5. Must unlock again for next reconfiguration

`default_nettype none

module scan_controller_macro #(
    parameter [7:0] MAGIC_WORD = 8'hA5
)(
`ifdef USE_POWER_PINS
    inout vccd1,
    inout vssd1,
`endif
    input  wire por_n,
    input  wire sys_reset_n,

    // Pad-facing scan signals
    input  wire pad_scan_clk,
    input  wire pad_scan_din,
    input  wire pad_scan_latch,
    output wire pad_scan_dout,

    // Chain-facing scan signals
    output wire chain_scan_clk,
    output wire chain_scan_din,
    output wire chain_scan_latch,
    input  wire chain_scan_dout
);

    wire reset_n = por_n & sys_reset_n;

    // Buffered local scan clock
    wire local_clk;
    tech_clkbuf u_lclk (.A(pad_scan_clk), .X(local_clk));

    // Security state machine
    reg [7:0] magic_sr;
    reg       unlocked;

    always @(posedge local_clk or negedge reset_n) begin
        if (!reset_n) begin
            magic_sr <= 8'h00;
            unlocked <= 1'b0;
        end else begin
            if (!unlocked) begin
                // Shift in and check for magic word
                magic_sr <= {magic_sr[6:0], pad_scan_din};
                if ({magic_sr[6:0], pad_scan_din} == MAGIC_WORD)
                    unlocked <= 1'b1;
            end else begin
                // Auto re-lock on latch assertion
                if (pad_scan_latch) begin
                    unlocked <= 1'b0;
                    magic_sr <= 8'h00;
                end
            end
        end
    end

    // Gated chain clock: only passes when unlocked
    tech_clkgate u_chain_clk (.CLK(pad_scan_clk), .GATE(unlocked), .GCLK(chain_scan_clk));

    // Gated chain latch and data
    wire safe_latch = unlocked & pad_scan_latch;

    tech_buf u_din_buf   (.A(pad_scan_din), .X(chain_scan_din));
    tech_buf u_latch_buf (.A(safe_latch),   .X(chain_scan_latch));

    // Scan data out: always connected for readback
    tech_buf u_dout_buf (.A(chain_scan_dout), .X(pad_scan_dout));

endmodule
