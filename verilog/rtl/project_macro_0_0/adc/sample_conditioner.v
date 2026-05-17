module sample_conditioner #(
    parameter DATA_W = 8
) (
    input  wire              clk,
    input  wire              rst_n,

    input  wire [DATA_W-1:0] new_sample,
    input  wire              valid,
    input  wire [DATA_W-1:0] minimum,
    input  wire              clear,

    output reg  [4:0]        sample_out,
    output reg               sample_valid,
    output reg               sample_received
);

reg [7:0] sample_ctr;

wire [DATA_W-1:0] diff;
wire [DATA_W-1:0] shifted;
wire [4:0]        raw5;
wire [4:0]        capped;

assign diff    = new_sample - minimum;
assign shifted = diff >> 1;
assign raw5    = shifted[4:0];
assign capped  = (|shifted[DATA_W-1:5]) ? 5'b11111 : raw5;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sample_out        <= 5'd0;
        sample_valid      <= 1'b0;
        sample_received <= 1'b0;
        sample_ctr      <= 8'd0;
    end else begin
        sample_valid      <= 1'b0;
        sample_received <= 1'b0;

        if (clear) begin
            sample_ctr <= 8'd0;
        end else if (valid) begin
            sample_out   <= capped;
            sample_valid <= 1'b1;

            if (sample_ctr == 8'd186) begin
                sample_received <= 1'b1;
                sample_ctr      <= 8'd0;
            end else begin
                sample_ctr <= sample_ctr + 8'd1;
            end
        end
    end
end

endmodule
