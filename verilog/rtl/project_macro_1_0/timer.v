module timer (
    input wire clk,
    input wire rst_n,
    input wire enable,
    input wire [15:0] tick_divider,
    output reg tick_pulse,
    output reg [15:0] tick_counter
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_counter <= 16'd0;
            tick_pulse <= 1'b0;
        end else if (!enable) begin
            tick_counter <= tick_divider;
            tick_pulse <= 1'b0;
        end else begin
            if (tick_counter == 16'd0) begin
                tick_counter <= tick_divider;
                tick_pulse <= 1'b1;
            end else begin
                tick_counter <= tick_counter - 16'd1;
                tick_pulse <= 1'b0;
            end
        end
    end
endmodule
