// TraceGuard-X ASIC — AUC Silicon Sprint
// Module : token_decoder
// Process: SKY130 Open PDK
// Authors: Omar Ahmed Fouad, Ahmed Tawfiq, Omar Ahmed Abdelaty
//
// RTL source — see docs/report/ for full module specification.

module token_decoder #(
    parameter MAX_STATES  = 16,
    parameter TOKEN_WIDTH = 8
) (
    input  wire                   clk,
    input  wire                   rst_n,

    input  wire                   learn_en,
    input  wire [8:0]             learn_addr,
    input  wire [TOKEN_WIDTH-1:0] learn_data,

    input  wire [TOKEN_WIDTH-1:0] token_in,
    output reg  [3:0]             mapped_id
);

    localparam MAX_CHARS = MAX_STATES - 1;

    reg [TOKEN_WIDTH-1:0] dict_regs [1:MAX_CHARS];


    wire [$clog2(MAX_STATES)-1:0] wr_index;
    assign wr_index = learn_addr[$clog2(MAX_STATES)-1:0] - 1'b1;

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 1; i <= MAX_CHARS; i = i + 1) begin
                dict_regs[i] <= {TOKEN_WIDTH{1'b0}};
            end
        end else if (learn_en) begin
            if (learn_addr >= 9'd2 && learn_addr <= (9'd1 + MAX_CHARS)) begin
                dict_regs[wr_index] <= learn_data;
            end
        end
    end

    integer j; 
    always @(*) begin
        mapped_id = 4'd0;

        for (j = MAX_CHARS; j >= 1; j = j - 1) begin
            if (token_in == dict_regs[j]) begin
                mapped_id = 4'(j); 
            end
        end
    end

endmodule
