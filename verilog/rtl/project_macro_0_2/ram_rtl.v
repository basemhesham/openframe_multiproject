// DFFRAM Behavioral RTL Model
// Matches the structural DFFRAM interface and timing behavior:
//   - 1-cycle read latency (EN0=1 + address → Do0 valid next cycle)
//   - Byte-granularity write enable (WE0)
//   - Output holds when EN0=0 (clock-gated output register)
//
// SPDX-License-Identifier: Apache-2.0

module DFFRAM #(
    parameter WORDS = 256,
    parameter WSIZE = 1          // word size in bytes
) (
    input  wire                    CLK,
    input  wire [WSIZE-1:0]        WE0,
    input  wire                    EN0,
    input  wire [$clog2(WORDS)-1:0] A0,
    input  wire [(WSIZE*8-1):0]    Di0,
    output reg  [(WSIZE*8-1):0]    Do0
);
    // Storage array
    reg [(WSIZE*8-1):0] mem [0:WORDS-1];

    integer i;

    integer k;

    
    initial begin
        for (k = 0; k < WORDS; k = k + 1) begin
            mem[k] = {WSIZE*8{1'b0}};
        end
    end

    always @(posedge CLK) begin
        if (EN0) begin
            // Write with byte enables
            for (i = 0; i < WSIZE; i = i + 1) begin
                if (WE0[i])
                    mem[A0][i*8 +: 8] <= Di0[i*8 +: 8];
            end
            // Read — output register updates only when enabled
            Do0 <= mem[A0];
        end
        // When EN0=0: Do0 holds (implicit in always block — no else clause)
    end
endmodule
