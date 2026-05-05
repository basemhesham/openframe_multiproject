// TraceGuard-X ASIC — AUC Silicon Sprint
// Module : RAM256_Banked
// Process: SKY130 Open PDK
// Authors: Omar Ahmed Fouad, Ahmed Tawfiq, Omar Ahmed Abdelaty
//
// RTL source — see docs/report/ for full module specification.

module RAM256_Banked (
    input  wire       CLK,
    input  wire [0:0] WE0,   // 1-bit Write Enable (WSIZE=1)
    input  wire       EN0,   // Chip Enable
    input  wire [7:0] A0,    // 8-bit Address (for 256 words)
    input  wire [7:0] Di0,   // 8-bit Data In
    output wire [7:0] Do0    // 8-bit Data Out
);

    DFFRAM #(
        .WORDS(256),
        .WSIZE(1)
    ) u_mem_core (
        .CLK(CLK),
        .WE0(WE0),
        .EN0(EN0),
        .A0(A0),
        .Di0(Di0),
        .Do0(Do0)
    );

endmodule
