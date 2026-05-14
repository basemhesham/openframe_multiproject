// =============================================================================
// tpm_mem.v — Unified Command / Response Buffer
// =============================================================================
// 256 bytes, split into two fixed regions:
//   [0x00 .. 0x7F]  CMD_BUF — host writes command here via SPI
//   [0x80 .. 0xFF]  RSP_BUF — processor writes response here
//
// Two independent byte-wide ports with no built-in arbitration.
// The top-level (tpm_top) enforces phase separation:
//   Phase IDLE/LOAD : SPI slave owns Port A (writes CMD_BUF)
//   Phase EXEC      : Command processor owns Port B (reads CMD, writes RSP)
//   Phase READ      : SPI slave owns Port A again (reads RSP_BUF)
//
// BOTH ports have 1-cycle read latency (registered output). Writes are
// synchronous. Port A write takes priority over Port B write if both target
// the same address on the same cycle (should not happen by phase separation).
// =============================================================================
`timescale 1ns/1ps

module tpm_mem (
    input  wire       clk,

    // Port A — SPI slave
    input  wire [7:0] pa_addr,
    input  wire [7:0] pa_wdata,
    input  wire       pa_we,
    output reg  [7:0] pa_rdata,   // FIX: registered (was combinational assign)

    // Port B — command processor
    input  wire [7:0] pb_addr,
    input  wire [7:0] pb_wdata,
    input  wire       pb_we,
    output reg  [7:0] pb_rdata
);

reg [7:0] mem [0:255];

integer j;
initial for (j=0; j<256; j=j+1) mem[j] = 8'h00;

// Synchronous writes — two independent always blocks (true dual-port)
always @(posedge clk) begin
    if (pa_we) mem[pa_addr] <= pa_wdata;
end

always @(posedge clk) begin
    if (pb_we) mem[pb_addr] <= pb_wdata;
end

// Registered reads — 1-cycle latency on both ports
always @(posedge clk) begin
    pa_rdata <= mem[pa_addr];   // FIX: registered read (was combinational)
    pb_rdata <= mem[pb_addr];
end

endmodule
