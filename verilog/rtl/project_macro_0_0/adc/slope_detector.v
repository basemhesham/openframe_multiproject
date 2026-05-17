module slope_detector #(
    parameter DATA_W = 8
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              enable,
    input  wire              valid,
    input  wire [DATA_W-1:0] sample_a,
    input  wire [DATA_W-1:0] sample_b,
    input  wire [DATA_W-1:0] thresh,
    output reg               slope_detected,
    output wire              backoff_active
);

reg [3:0] backoff_ctr;
wire [DATA_W-1:0] rise_mag;
wire slope_now;

assign rise_mag = sample_a - sample_b;
assign slope_now = (sample_a > sample_b) && (rise_mag > thresh);
assign backoff_active = (backoff_ctr != 4'd0);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        backoff_ctr    <= 4'd0;
        slope_detected <= 1'b0;
    end else begin
        slope_detected <= 1'b0;

        if (valid && (backoff_ctr != 4'd0)) begin
            backoff_ctr <= backoff_ctr - 4'd1;
        end

        if (enable && valid && (backoff_ctr == 4'd0) && slope_now) begin
            slope_detected <= 1'b1;
            backoff_ctr    <= 4'd8;
        end
    end
end

endmodule
