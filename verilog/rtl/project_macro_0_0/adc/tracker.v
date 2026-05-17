module tracker #(
    parameter DATA_W = 8
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              enable,
    input  wire              valid,
    input  wire              init_load,
    input  wire              clear_alarms,

    input  wire [DATA_W-1:0] init_rolling_min,
    input  wire [DATA_W-1:0] new_sample,
    input  wire [DATA_W-1:0] peak1_val,

    input  wire [DATA_W-1:0] rs_window,
    input  wire [DATA_W-1:0] max_window,
    input  wire [3:0]        arm_ctr,

    input  wire              slope_event_seen,

    output reg               rs_alarm,
    output reg               max_window_alarm,

    output reg  [DATA_W-1:0] rolling_min,
    output reg  [DATA_W-1:0] rolling_max
);

reg rolling_max_valid;
reg [DATA_W-1:0] next_min;
reg [DATA_W-1:0] next_max;
reg [DATA_W-1:0] rs_gap;
reg [DATA_W-1:0] max_gap;

always @(*) begin
    next_min = rolling_min;
    if (new_sample < rolling_min) begin
        next_min = new_sample;
    end

    next_max = rolling_max;
    if ((arm_ctr >= 4'd15) && ((~rolling_max_valid) || (new_sample > rolling_max))) begin
        next_max = new_sample;
    end

    if (peak1_val > next_min) begin
        rs_gap = peak1_val - next_min;
    end else begin
        rs_gap = {DATA_W{1'b0}};
    end

    if (peak1_val > next_max) begin
        max_gap = peak1_val - next_max;
    end else begin
        max_gap = {DATA_W{1'b0}};
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rs_alarm          <= 1'b0;
        max_window_alarm  <= 1'b0;
        rolling_min       <= {DATA_W{1'b1}};
        rolling_max       <= {DATA_W{1'b0}};
        rolling_max_valid <= 1'b0;
    end else begin
        if (init_load) begin
            rolling_min       <= init_rolling_min;
            rolling_max       <= {DATA_W{1'b0}};
            rolling_max_valid <= 1'b0;
            rs_alarm          <= 1'b0;
            max_window_alarm  <= 1'b0;
        end else if (clear_alarms) begin
            rs_alarm          <= 1'b0;
            max_window_alarm  <= 1'b0;
        end else if (enable && valid) begin
            rolling_min <= next_min;

            if (arm_ctr >= 4'd15) begin
                if ((~rolling_max_valid) || (new_sample > rolling_max)) begin
                    rolling_max       <= new_sample;
                    rolling_max_valid <= 1'b1;
                end
            end

            if (rs_gap > rs_window) begin
                rs_alarm <= 1'b1;
            end

            if ((arm_ctr >= 4'd15) && rolling_max_valid && (max_gap < max_window) && (~slope_event_seen)) begin
                max_window_alarm <= 1'b1;
            end
        end
    end
end

endmodule
