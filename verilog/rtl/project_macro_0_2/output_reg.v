// TraceGuard-X ASIC — AUC Silicon Sprint
// Module : output_reg
// Process: SKY130 Open PDK
// Authors: Omar Ahmed Fouad, Ahmed Tawfiq, Omar Ahmed Abdelaty
//
// RTL source — see docs/report/ for full module specification.

module output_reg #(
    parameter MATCH_HOLD_CYCLES = 4
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,

    // from processing blocks
    input  wire       alert_in,
    input  wire       match_in,
    input  wire       ac_processing,
    input  wire [1:0] mode,
    input  wire [7:0] score_in,
    input  wire [2:0] pattern_id_in,
    input  wire       watchdog_alert,

    // command interface
    input  wire       send_status_req,
    input  wire       send_result_req,
    input  wire [7:0] match_count_in,
    input  wire [7:0] confidence_in,

    // UART TX interface
    output reg  [7:0] tx_data,
    output reg        tx_valid,
    input  wire       tx_ready,

    // GPIO outputs
    output reg        gpio_alert,
    output reg        gpio_match,
    output reg        gpio_busy,
    output reg        gpio_ready
);

    // TX FSM States (One-Hot Encoded)
    localparam [2:0] TX_S_IDLE   = 3'b001,
                     TX_S_STATUS = 3'b010,
                     TX_S_RESULT = 3'b100;

    reg [2:0] tx_state;
    reg [2:0] byte_idx;
    reg [7:0] tx_buf [0:4];
    integer i;

    reg       pending_status;
    reg       pending_result;

    reg [3:0] match_hold_r;

    // GPIO Drive Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {gpio_alert, gpio_match, gpio_busy, gpio_ready} <= 4'd0;
            match_hold_r <= 4'd0;
        end else begin
            if (en) begin
                if (mode == 2'b00) begin 
                    {gpio_alert, gpio_match, gpio_busy, gpio_ready} <= 4'd0;
                    match_hold_r <= 4'd0;
                end else begin
                    if (match_in) begin
                        match_hold_r <= MATCH_HOLD_CYCLES[3:0];
                    end else if (ac_processing) begin
                        // FIX: Kill the match hold immediately if a new token is being processed
                        match_hold_r <= 4'd0; 
                    end else if (match_hold_r > 0) begin
                        match_hold_r <= match_hold_r - 1'b1;
                    end

                    gpio_alert <= alert_in || watchdog_alert;
                    gpio_match <= (match_in) || (match_hold_r > 0);
                    gpio_busy  <= ac_processing;
                    gpio_ready <= (mode == 2'b10); 
                end
            end
        end
    end

    // UART TX Response Machine 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state       <= TX_S_IDLE;
            byte_idx       <= 3'd0;
            tx_data        <= 8'd0;
            {tx_valid, pending_status, pending_result} <= 3'd0;
            for (i=0; i<5; i=i+1) tx_buf[i] <= 8'd0;
        end else if (en) begin
            if (send_status_req) pending_status <= 1'b1;
            if (send_result_req) pending_result <= 1'b1;

            tx_valid <= 1'b0; 

            case (tx_state)
                TX_S_IDLE: begin
                    byte_idx <= 3'd0;
                    if (pending_status || send_status_req) begin
                        pending_status <= 1'b0;
                        tx_buf[0]      <= 8'hB0;
                        tx_buf[1]      <= score_in;
                        tx_buf[2]      <= {5'b0, pattern_id_in};
                        tx_buf[3]      <= {mode, 4'b0, gpio_alert, gpio_match};
                        tx_buf[4]      <= 8'h00;
                        tx_state       <= TX_S_STATUS;
                    end else if (pending_result || send_result_req) begin
                        pending_result <= 1'b0;
                        tx_buf[0]      <= 8'hB1;
                        tx_buf[1]      <= score_in;
                        tx_buf[2]      <= match_count_in;
                        tx_buf[3]      <= confidence_in;
                        tx_buf[4]      <= {gpio_alert, 7'b0};
                        tx_state       <= TX_S_RESULT;
                    end
                end

                TX_S_STATUS, TX_S_RESULT: begin
                    if (tx_ready && !tx_valid) begin
                        tx_data  <= tx_buf[byte_idx];
                        tx_valid <= 1'b1;

                        if (byte_idx == 3'd4) begin
                            tx_state <= TX_S_IDLE;
                        end else begin
                            byte_idx <= byte_idx + 1'b1;
                        end
                    end
                end

                default: tx_state <= TX_S_IDLE;
            endcase
        end
    end

endmodule
