module ADC_Big_Wrap #(
    parameter DATA_W = 12,
    parameter AVG_ENABLE = 1'b0,
    parameter CLK = 4_000_000
)(
    input  wire clk,
    input  wire rst_n,


    input  wire              adc_valid,
    input  wire [7:0]        adc_in_data,
    
    input  wire              command_ready,
    input  wire [DATA_W-1:0] slope_thresh,
    input  wire [DATA_W-1:0] rs_window,
    input  wire [DATA_W-1:0] max_window,
    input  wire [DATA_W-1:0] tolerance,
    input  wire [DATA_W-1:0] floor_offset,

    output wire       clear,
    output wire [4:0] sample_out,     //0x00 to 0x20
    output wire       sample_valid,
    output reg        command_valid
);

    reg                 command_startofpacket;
    reg                 command_endofpacket;

    // ============================================================
    // Averaging logic
    // ============================================================

    localparam integer SAMPLE_PERIOD = CLK / 125;

    localparam IDLE       = 3'd0;
    localparam WAIT_COUNT = 3'd1;
    localparam SEND_CMD   = 3'd2;
    localparam WAIT_ADC   = 3'd3;
    localparam AVG_DONE   = 3'd4;

    (* mark_debug = "true" *) reg [2:0] current_state;
    reg [2:0] next_state;

    reg [$clog2(SAMPLE_PERIOD):0] sample_counter;

    // counts 0 to 7
    reg [2:0] sample_index; 

    // 12-bit ADC max = 4095
    // 4095 * 8 = 32760
    // needs 15 bits
    // DATA_W+3 bits is enough
    reg [DATA_W+2:0] sample_sum;

    (* mark_debug = "true" *) reg [DATA_W-1:0] adc_avg_data;
    (* mark_debug = "true" *) reg              adc_avg_valid;

    (* mark_debug = "true" *) wire [DATA_W-1:0] shifted_out;
    (* mark_debug = "true" *) wire              shifted_out_valid;
    (* mark_debug = "true" *) wire [DATA_W-1:0] frame_min;
    (* mark_debug = "true" *) wire              tol_alarm_out;
    (* mark_debug = "true" *) wire              rs_alarm_out;
    (* mark_debug = "true" *) wire              max_win_alarm_out;
    (* mark_debug = "true" *) wire              sample_received;

    assign clear = tol_alarm_out | rs_alarm_out | max_win_alarm_out;

    // ============================================================
    // ECG preprocessor instance
    // ============================================================

    ecg_preprocessor #(
        .DATA_W(DATA_W)
    ) ecg_preprocessor_inst (
        .clk                (clk),
        .rst_n              (rst_n),

        .adc_in             (adc_avg_data),
        .adc_valid          (adc_avg_valid),

        .sample_received    (sample_received),

        .slope_thresh       (slope_thresh),
        .rs_window          (rs_window),
        .max_window         (max_window),
        .tolerance          (tolerance),
        .floor_offset       (floor_offset),

        .shifted_out        (shifted_out),
        .shifted_out_valid  (shifted_out_valid),

        .frame_min    (frame_min),

        .tol_alarm_out      (tol_alarm_out),
        .rs_alarm_out       (rs_alarm_out),
        .max_win_alarm_out  (max_win_alarm_out)
    );

    sample_conditioner #(
        .DATA_W(DATA_W)
    ) sample_conditioner_inst (
        .clk(clk),
        .rst_n(rst_n),

        .new_sample(shifted_out),
        .valid(shifted_out_valid),
        .minimum(frame_min),
        .clear(clear),

        .sample_out(sample_out),
        .sample_valid(sample_valid),
        .sample_received(sample_received)
    );

    // ============================================================
    // FSM state register
    // ============================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // ============================================================
    // FSM next-state logic
    // ============================================================

    always @(*) begin
        next_state = current_state;

        case (current_state)

            IDLE: begin
                next_state = WAIT_COUNT;
            end

            WAIT_COUNT: begin
                if (sample_counter == SAMPLE_PERIOD - 1) begin
                    next_state = SEND_CMD;
                end
            end

            SEND_CMD: begin
                if (command_ready) begin
                    next_state = WAIT_ADC;
                end
            end

            WAIT_ADC: begin
                if (adc_valid) begin
                    if (!AVG_ENABLE || (sample_index == 3'd7)) begin
                        next_state = AVG_DONE;
                    end else begin
                        next_state = SEND_CMD;
                    end
                end
            end

            AVG_DONE: begin
                next_state = WAIT_COUNT;
            end

            default: begin
                next_state = IDLE;
            end

        endcase
    end

    // ============================================================
    // FSM output / datapath logic
    // ============================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_counter          <= 17'd0;
            sample_index            <= 3'd0;
            sample_sum              <= {DATA_W+3{1'b0}};

            adc_avg_data            <= {DATA_W{1'b0}};
            adc_avg_valid           <= 1'b0;

            command_valid           <= 1'b0;
            command_startofpacket   <= 1'b0;
            command_endofpacket     <= 1'b0;
        end else begin

            // Defaults every clock
            adc_avg_valid           <= 1'b0;

            command_valid           <= 1'b0;
            command_startofpacket   <= 1'b0;
            command_endofpacket     <= 1'b0;

            case (current_state)

                IDLE: begin
                    sample_counter <= 17'd0;
                    sample_index   <= 3'd0;
                    sample_sum     <= {DATA_W+3{1'b0}};
                end

                WAIT_COUNT: begin
                    if (sample_counter == SAMPLE_PERIOD - 1) begin
                        sample_counter <= 17'd0;
                    end else begin
                        sample_counter <= sample_counter + 17'd1;
                    end
                end

                SEND_CMD: begin
                    command_valid         <= 1'b1;
                    command_startofpacket <= 1'b1;
                    command_endofpacket   <= 1'b1;
                end

                WAIT_ADC: begin
                    if (adc_valid) begin
                        if (AVG_ENABLE) begin
                            sample_sum <= sample_sum + adc_in_data;

                            if (sample_index == 3'd7) begin
                                sample_index <= 3'd0;
                            end else begin
                                sample_index <= sample_index + 3'd1;
                            end
                        end else begin
                            adc_avg_data  <= adc_in_data;
                            adc_avg_valid <= 1'b1;
                        end
                    end
                end

                AVG_DONE: begin
                    if (AVG_ENABLE) begin
                        adc_avg_data  <= sample_sum >> 3;
                        adc_avg_valid <= 1'b1;
                    end

                    sample_sum    <= {DATA_W+3{1'b0}};
                end

                default: begin
                    sample_counter <= 17'd0;
                    sample_index   <= 3'd0;
                    sample_sum     <= {DATA_W+3{1'b0}};
                end

            endcase
        end
    end

endmodule