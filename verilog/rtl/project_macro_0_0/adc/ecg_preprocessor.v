module ecg_preprocessor #(
    parameter DATA_W = 8
) (
    input  wire              clk,
    input  wire              rst_n,

    input  wire [DATA_W-1:0] adc_in,
    input  wire              adc_valid,

    input  wire              sample_received,

    input  wire [DATA_W-1:0] slope_thresh,
    input  wire [DATA_W-1:0] rs_window,
    input  wire [DATA_W-1:0] max_window,
    input  wire [DATA_W-1:0] tolerance,
    input  wire [DATA_W-1:0] floor_offset,

    output wire [DATA_W-1:0] shifted_out,
    output wire              shifted_out_valid,

    output wire [DATA_W-1:0] frame_min,

    output reg               tol_alarm_out,
    output wire              rs_alarm_out,
    output wire              max_win_alarm_out
);

localparam S_FILL      = 2'd0;
localparam S_DETECT_P1 = 2'd1;
// localparam S_BACKOFF   = 3'd2;
localparam S_TRACK     = 2'd2;
localparam S_WAIT      = 2'd3;

reg [2:0] state;
reg [3:0] fill_ctr;
// reg [2:0] pause_ctr;
reg [3:0] arm_ctr;

reg [DATA_W-1:0] peak2_val;
reg [DATA_W-1:0] abs_diff;
reg [DATA_W-1:0] rolling_min_seed;

reg tracker_init_load;
reg tracker_clear_alarms;
reg tracker_enable;
reg slope_enable;

wire slope_detected;
wire slope_backoff_active;
wire [DATA_W-1:0] b0;
wire [DATA_W-1:0] b1;
wire [DATA_W-1:0] b2;
wire [DATA_W-1:0] b3;
wire [DATA_W-1:0] b4;
wire [DATA_W-1:0] b5;
wire [DATA_W-1:0] b6;
wire [DATA_W-1:0] b7;

wire [DATA_W-1:0] rolling_min_w;
wire [DATA_W-1:0] rolling_max_w;
wire rs_alarm_w;
wire max_alarm_w;

wire [DATA_W-1:0] max5_buf;
wire [DATA_W-1:0] min3_buf;
wire [DATA_W-1:0] min3_minus_floor;
wire slope_seen_now;
wire peak_found;

reg  [DATA_W-1:0] peak1_val;
reg               valid_pair_found;

assign slope_seen_now  = slope_backoff_active | slope_detected;
assign frame_min = min3_minus_floor;
assign rs_alarm_out    = rs_alarm_w;
assign max_win_alarm_out = max_alarm_w;
assign peak_found = ((state != S_FILL) && (state != S_DETECT_P1)) ? 1'b1 : 1'b0;

assign max5_buf = max5(b0, b1, b2, b3, b4);
assign min3_buf = min3(b5, b6, b7);
assign min3_minus_floor = (min3_buf > floor_offset) ? (min3_buf - floor_offset) : {DATA_W{1'b0}};

sample_buffer #(.DATA_W(DATA_W)) u_sample_buffer (
    .clk(clk),
    .rst_n(rst_n),
    .adc_in(adc_in),
    .valid(adc_valid),
    .shifted_out(shifted_out),
    .shifted_out_valid(shifted_out_valid),
    .peak_found(peak_found),
    .b0(b0),
    .b1(b1),
    .b2(b2),
    .b3(b3),
    .b4(b4),
    .b5(b5),
    .b6(b6),
    .b7(b7)
);

slope_detector #(.DATA_W(DATA_W)) u_slope_detector (
    .clk(clk),
    .rst_n(rst_n),
    .enable(slope_enable),
    .valid(adc_valid),
    .sample_a(b3),
    .sample_b(b4),
    .thresh(slope_thresh),
    .slope_detected(slope_detected),
    .backoff_active(slope_backoff_active)
);

tracker #(.DATA_W(DATA_W)) u_tracker (
    .clk(clk),
    .rst_n(rst_n),
    .enable(tracker_enable),
    .valid(adc_valid),
    .init_load(tracker_init_load),
    .clear_alarms(tracker_clear_alarms),
    .init_rolling_min(rolling_min_seed),
    .new_sample(b4),
    .peak1_val(peak1_val),
    .rs_window(rs_window),
    .max_window(max_window),
    .arm_ctr(arm_ctr),
    .slope_event_seen(slope_seen_now),
    .rs_alarm(rs_alarm_w),
    .max_window_alarm(max_alarm_w),
    .rolling_min(rolling_min_w),
    .rolling_max(rolling_max_w)
);

always @(*) begin
    //tracker_init_load   = 1'b0;
    //tracker_clear_alarms = 1'b0;
    tracker_enable      = 1'b0;
    slope_enable        = 1'b0;

    case (state)
        S_FILL: begin
            slope_enable   = 1'b0;
            tracker_enable = 1'b0;
        end

        S_DETECT_P1: begin
            slope_enable   = 1'b1;
            tracker_enable = 1'b0;
        end

        // S_BACKOFF: begin
        //     slope_enable   = 1'b0;
        //     tracker_enable = 1'b0;
        // end

        S_TRACK: begin
            slope_enable   = 1'b1;
            tracker_enable = 1'b1;
        end

        S_WAIT: begin
            slope_enable   = 1'b0;
            tracker_enable = 1'b0;
        end

        default: begin
            slope_enable   = 1'b0;
            tracker_enable = 1'b0;
        end
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state            <= S_FILL;
        fill_ctr         <= 4'd0;
        // pause_ctr        <= 3'd0;
        arm_ctr          <= 4'd0;
        peak1_val        <= {DATA_W{1'b0}};
        peak2_val        <= {DATA_W{1'b0}};
        abs_diff         <= {DATA_W{1'b0}};
        rolling_min_seed <= {DATA_W{1'b1}};
        valid_pair_found <= 1'b0;
        tol_alarm_out    <= 1'b0;
    end else begin
        valid_pair_found <= 1'b0;
        tol_alarm_out    <= 1'b0;
        tracker_init_load <= 1'b0;
        tracker_clear_alarms <= 1'b0;

        case (state)
            S_FILL: begin
                if (adc_valid) begin
                    if (fill_ctr == 4'd7) begin
                        fill_ctr <= 4'd0;
                        state    <= S_DETECT_P1;
                    end else begin
                        fill_ctr <= fill_ctr + 4'd1;
                    end
                end
            end

            S_DETECT_P1: begin
                arm_ctr <= 4'd0;
                if (slope_detected) begin
                    peak1_val        <= max5_buf;
                    rolling_min_seed <= min3_minus_floor;
                    // pause_ctr        <= 3'd0;

                    tracker_init_load  <= 1'b1;
                    tracker_clear_alarms <= 1'b1;
                    state              <= S_TRACK;
                end
            end

            // S_BACKOFF: begin
            //     if (adc_valid) begin
            //         if (pause_ctr == 3'd7) begin
            //             pause_ctr          <= 3'd0;
            //             arm_ctr            <= 3'd0;
            //             tracker_init_load  <= 1'b1;
            //             tracker_clear_alarms <= 1'b1;
            //             state              <= S_TRACK;
            //         end else begin
            //             pause_ctr <= pause_ctr + 3'd1;
            //         end
            //     end
            // end

            S_TRACK: begin
                if (adc_valid && (arm_ctr != 4'd15)) begin
                    arm_ctr <= arm_ctr + 4'd1;
                end

                if (rs_alarm_w || max_alarm_w) begin
                    tracker_clear_alarms <= 1'b1;
                    arm_ctr              <= 4'd0;
                    state                <= S_DETECT_P1;
                end else if (slope_detected) begin

                    if (((peak1_val >= max5_buf) ? (peak1_val - max5_buf) : (max5_buf - peak1_val)) > tolerance) begin
                        tol_alarm_out      <= 1'b1;

                        peak1_val          <= max5_buf;
                        rolling_min_seed   <= min3_minus_floor;
                        tracker_init_load  <= 1'b1;
                        tracker_clear_alarms <= 1'b1;
                        state              <= S_TRACK;

                        // pause_ctr          <= 4'd0;
                        // state              <= S_BACKOFF;
                    end else begin
                        valid_pair_found   <= 1'b1;
                        tracker_clear_alarms <= 1'b1;
                        state              <= S_WAIT;
                    end
                end
            end

            S_WAIT: begin
                if (sample_received) begin
                    arm_ctr <= 4'd0;
                    state   <= S_DETECT_P1;
                end
            end

            default: begin
                state <= S_FILL;
            end
        endcase
    end
end

function [DATA_W-1:0] vmax2;
    input [DATA_W-1:0] a;
    input [DATA_W-1:0] b;
    begin
        if (a >= b) begin
            vmax2 = a;
        end else begin
            vmax2 = b;
        end
    end
endfunction

function [DATA_W-1:0] vmin2;
    input [DATA_W-1:0] a;
    input [DATA_W-1:0] b;
    begin
        if (a <= b) begin
            vmin2 = a;
        end else begin
            vmin2 = b;
        end
    end
endfunction

function [DATA_W-1:0] max5;
    input [DATA_W-1:0] x0;
    input [DATA_W-1:0] x1;
    input [DATA_W-1:0] x2;
    input [DATA_W-1:0] x3;
    input [DATA_W-1:0] x4;
    reg [DATA_W-1:0] m0;
    reg [DATA_W-1:0] m1;
    begin
        m0 = vmax2(x0, x1);
        m1 = vmax2(x2, x3);
        max5 = vmax2(vmax2(m0, m1), x4);
    end
endfunction

function [DATA_W-1:0] min3;
    input [DATA_W-1:0] x0;
    input [DATA_W-1:0] x1;
    input [DATA_W-1:0] x2;
    begin
        min3 = vmin2(vmin2(x0, x1), x2);
    end
endfunction

endmodule
