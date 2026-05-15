module scan_chain #(parameter WIDTH = 256) (
    input wire clk,
    input wire rst_n,
    input wire scan_en,
    input wire scan_in,
    input wire [WIDTH-1:0] parallel_in,
    output wire scan_out
);
    reg [WIDTH-1:0] scan_reg;
    assign scan_out = scan_reg[WIDTH-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_reg <= {WIDTH{1'b0}};
        end else if (scan_en) begin
            scan_reg <= {scan_reg[WIDTH-2:0], scan_in};
        end else begin
            scan_reg <= parallel_in;
        end
    end
endmodule
