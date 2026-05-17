module sample_buffer #(
    parameter DATA_W = 8
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire [DATA_W-1:0] adc_in,
    input  wire              valid,
    input  wire              peak_found,
    output reg  [DATA_W-1:0] shifted_out,
    output reg               shifted_out_valid,
    output reg  [DATA_W-1:0] b0,
    output reg  [DATA_W-1:0] b1,
    output reg  [DATA_W-1:0] b2,
    output reg  [DATA_W-1:0] b3,
    output reg  [DATA_W-1:0] b4,
    output reg  [DATA_W-1:0] b5,
    output reg  [DATA_W-1:0] b6,
    output reg  [DATA_W-1:0] b7
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        shifted_out       <= {DATA_W{1'b0}};
        shifted_out_valid <= 1'b0;
        b0 <= {DATA_W{1'b0}};
        b1 <= {DATA_W{1'b0}};
        b2 <= {DATA_W{1'b0}};
        b3 <= {DATA_W{1'b0}};
        b4 <= {DATA_W{1'b0}};
        b5 <= {DATA_W{1'b0}};
        b6 <= {DATA_W{1'b0}};
        b7 <= {DATA_W{1'b0}};
    end else begin
        shifted_out_valid <= 1'b0;
        if (valid) begin
            shifted_out       <= b7;
            if(peak_found) begin
                shifted_out_valid <= 1'b1;
            end
            b7 <= b6;
            b6 <= b5;
            b5 <= b4;
            b4 <= b3;
            b3 <= b2;
            b2 <= b1;
            b1 <= b0;
            b0 <= adc_in;
        end
    end
end

endmodule
