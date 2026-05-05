// TraceGuard-X ASIC — AUC Silicon Sprint
// Module : sliding_window
// Process: SKY130 Open PDK
// Authors: Omar Ahmed Fouad, Ahmed Tawfiq, Omar Ahmed Abdelaty
//
// RTL source — see docs/report/ for full module specification.

module sliding_window #(
    parameter SLIDE_MAX_WIN = 32
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,
    input  wire [7:0] token_in,
    input  wire       token_valid,
    input  wire [4:0] window_size,
    input  wire       flush,
    output wire [7:0] window_out, 
    output wire       window_ready
);


    wire _unused = &{1'b0, window_size};

    reg [7:0] tok_r;
    reg       vld_r;

    assign window_out   = tok_r;
    assign window_ready = vld_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tok_r <= 8'h00;
            vld_r <= 1'b0;
        end else if (flush) begin
            vld_r <= 1'b0;
        end else if (en) begin
            tok_r <= token_in;
            vld_r <= token_valid;
        end
    end

endmodule
