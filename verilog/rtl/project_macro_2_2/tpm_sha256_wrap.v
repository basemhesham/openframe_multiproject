// =============================================================================
// tpm_sha256_wrap.v — SHA-256 Engine Wrapper
// =============================================================================
// Thin layer around secworks/sha256_core that adds:
//   1. FIPS 180-4 padding on the final block
//   2. start/ready handshake so the command processor does not need to know
//      the exact cycle count of the core
//   3. Multi-block streaming: first=1 initialises, first=0 continues
//
// The secworks sha256_core interface:
//   init   — start a new hash (equivalent to: first block)
//   next   — feed the next block of an ongoing hash
//   block  — 512-bit input block
//   ready  — core is idle, can accept init or next
//   digest       — 256-bit output
//   digest_valid — digest is valid (asserted same cycle ready goes high)
//
// This wrapper hides those details. The command processor just does:
//   1. Set sha_first, sha_last, sha_last_len, sha_block, sha_tbits
//   2. Pulse sha_start
//   3. Wait for sha_done
//   4. Read sha_digest
//
// =============================================================================
`timescale 1ns/1ps

module tpm_sha256_wrap (
    input  wire          clk,
    input  wire          rstn,

    // Command processor interface
    input  wire          sha_start,     // pulse: begin processing this block
    input  wire          sha_first,     // 1=init new hash, 0=continue existing
    input  wire          sha_last,      // 1=this is the final block (pad it)
    input  wire [8:0]    sha_last_len,  // valid bytes in final block (0-64)
    input  wire [511:0]  sha_block,     // 512-bit input block (unpadded)
    input  wire [63:0]   sha_tbits,     // total message length in bits (padding)

    output reg           sha_ready,     // 1 = idle, ready for sha_start
    output reg           sha_done,      // 1-cycle pulse: digest is valid
    output reg  [255:0]  sha_digest     // hash result
);

// ---------------------------------------------------------------------------
// Padding function: append 0x80, zeros, 64-bit length to the final block.
// Called combinationally to produce the padded version of sha_block.
// ---------------------------------------------------------------------------
function [511:0] pad;
    input [511:0] raw;
    input [8:0]   vb;    // valid bytes (0..64)
    input [63:0]  tb;    // total bits
    integer b;
    reg [511:0] p;
    begin
        p = raw;
        // Zero bytes beyond valid data
        for (b = 0; b < 64; b = b + 1)
            if (b >= vb) p[511 - b*8 -: 8] = 8'h00;
        // Set 0x80 byte right after valid data
        if (vb < 64) p[511 - vb*8 -: 8] = 8'h80;
        // Append 64-bit total length in lowest 8 bytes (big-endian)
        if (vb <= 55) p[63:0] = tb;
        // If vb > 55 the length won't fit — caller must send an extra block.
        pad = p;
    end
endfunction

// ---------------------------------------------------------------------------
// Core wires
// ---------------------------------------------------------------------------
reg          c_init, c_next;
reg  [511:0] c_block;
wire         c_ready;
wire         c_dv;
wire [255:0] c_digest;

// ---------------------------------------------------------------------------
// State machine: IDLE → RUNNING → DONE
// ---------------------------------------------------------------------------
localparam S_IDLE = 2'd0;
localparam S_RUN  = 2'd1;   // block sent, waiting for core to go not-ready
localparam S_WAIT = 2'd2;   // waiting for core to come back ready with result

reg [1:0] state;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        state     <= S_IDLE;
        sha_ready <= 1'b1;
        sha_done  <= 1'b0;
        sha_digest <= 256'h0;
        c_init    <= 1'b0;
        c_next    <= 1'b0;
        c_block   <= 512'h0;
    end else begin
        c_init   <= 1'b0;
        c_next   <= 1'b0;
        sha_done <= 1'b0;

        case (state)
        S_IDLE: begin
            sha_ready <= 1'b1;
            if (sha_start) begin
                sha_ready <= 1'b0;
                // Build padded or raw block
                c_block <= sha_last
                    ? pad(sha_block, sha_last_len, sha_tbits)
                    : sha_block;
                // Assert init or next to core
                if (sha_first) c_init <= 1'b1;
                else           c_next <= 1'b1;
                state <= S_RUN;
            end
        end

        S_RUN: begin
            // Wait for core to de-assert ready (takes 1-2 cycles)
            if (!c_ready) state <= S_WAIT;
        end

        S_WAIT: begin
            // Wait for core to finish and re-assert ready
            if (c_ready) begin
                if (c_dv) begin
                    sha_digest <= c_digest;
                    sha_done   <= 1'b1;
                end
                state     <= S_IDLE;
                sha_ready <= 1'b1;
            end
        end
        endcase
    end
end

// ---------------------------------------------------------------------------
// secworks/sha256_core instantiation
// Clone: https://github.com/secworks/sha256
// Required files:
//   cores/sha256/src/rtl/sha256_core.v
//   cores/sha256/src/rtl/sha256_w_mem.v
// ---------------------------------------------------------------------------
sha256_core u_core (
    .clk          (clk),
    .reset_n      (rstn),
    .init         (c_init),
    .next         (c_next),
    .mode         (1'b1),       // 1 = SHA-256, 0 = SHA-224
    .block        (c_block),
    .ready        (c_ready),
    .digest       (c_digest),
    .digest_valid (c_dv)
);

endmodule
