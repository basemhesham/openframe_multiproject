// =============================================================================
// tpm_pcr_bank.v — Platform Configuration Registers
// =============================================================================
// 4 registers × 256 bits each (PCR 0-3).
//
// EXTEND is the only write path. There is no direct-write instruction.
//   new_PCR[n] = SHA256( old_PCR[n] || measurement )
//
// The command processor computes that SHA256 result externally and passes
// it here as ext_digest. This module only stores it.
//
// All PCRs reset to 0x00..00 on power-on (rstn low).
// =============================================================================
`timescale 1ns/1ps

module tpm_pcr_bank (
    input  wire         clk,
    input  wire         rstn,

    // Extend write port
    input  wire [1:0]   ext_sel,       // which PCR (0-3)
    input  wire [255:0] ext_digest,    // new value = SHA256(old||meas)
    input  wire         ext_valid,     // pulse: latch ext_digest

    // Read port (combinational, 1-cycle latency)
    input  wire [1:0]   rd_sel,
    output wire [255:0] rd_value,

    // Individual PCR outputs (for quote / attestation)
    output wire [255:0] pcr0,
    output wire [255:0] pcr1,
    output wire [255:0] pcr2,
    output wire [255:0] pcr3
);

reg [255:0] pcr [0:3];
integer i;

always @(posedge clk or negedge rstn) begin
    if (!rstn)
        for (i=0; i<4; i=i+1) pcr[i] <= 256'h0;
    else if (ext_valid)
        pcr[ext_sel] <= ext_digest;
end

assign rd_value = pcr[rd_sel];
assign pcr0 = pcr[0];
assign pcr1 = pcr[1];
assign pcr2 = pcr[2];
assign pcr3 = pcr[3];

endmodule
