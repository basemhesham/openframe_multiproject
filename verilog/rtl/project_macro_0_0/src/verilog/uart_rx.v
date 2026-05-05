//==============================================================================
//  Module      : uart_rx
//  Author      : Mohamed Tarek
//  Date        : Aug 2025
//  Course      : NTI Verilog Course
//==============================================================================

`default_nettype none
module uart_rx (
    input  wire         clk,       // system clock (100 MHz)
    input  wire         arst_n,    // async reset, active low
    input  wire         rst,       // sync reset
    input  wire         rx_en,     // enable signal
    input  wire [31:0]  baudiv,    // baud divider
    input  wire         rx,        // serial RX input

    output wire         rx_busy,   // receiver is busy
    output wire         rx_done,   // high when reception is done
    output wire         rx_err,    // high when framing error
    output reg  [7:0]   rx_data    // received byte
);

    //-------------------------
    // State encoding
    //-------------------------
    localparam [2:0] IDLE  = 3'd0,
                     START = 3'd1,
                     DATA  = 3'd2,
                     STOP  = 3'd3,
                     DONE  = 3'd4,
                     ERR   = 3'd5;

    reg [2:0] state, next_state;
    reg [2:0] bit_idx;   // counts 0..7 bits

    //-------------------------
    // Baud Counter
    //-------------------------
    reg [31:0] baud_cnt;
    wire baud_done = (baud_cnt == 0);
    reg        baud_load;
    reg [31:0] baud_val;

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n)
            baud_cnt <= 0;
        else if (rst)
            baud_cnt <= 0;
        else if (baud_load)
            baud_cnt <= baud_val;
        else if (baud_cnt != 0)
            baud_cnt <= baud_cnt - 1;
    end

    //-------------------------
    // Edge Detector
    //-------------------------
    reg rx_d1, rx_d2;
    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            rx_d1 <= 1'b1;
            rx_d2 <= 1'b1;
        end else begin
            rx_d1 <= rx;
            rx_d2 <= rx_d1;
        end
    end

    wire falling_edge = (rx_d2 == 1'b1 && rx_d1 == 1'b0);

    //-------------------------
    // FSM Next-state logic
    //-------------------------
    reg sipo_en;

    always @(*) begin
        next_state = state;
        baud_load  = 0;
        baud_val   = 0;
        sipo_en    = 0;

        case (state)
            IDLE: begin
                if (rx_en && falling_edge) begin
                    baud_load  = 1;
                    baud_val   = (baudiv >> 1); // half bit for start center
                    next_state = START;
                end
            end

            START: begin
                if (baud_done) begin
                    if (rx == 1'b0) begin
                        baud_load  = 1;
                        baud_val   = baudiv - 1;
                        next_state = DATA;
                    end else begin
                        next_state = IDLE; // false start
                    end
                end
            end

            DATA: begin
                if (baud_done) begin
                    sipo_en    = 1;
                    baud_load  = 1;
                    baud_val   = baudiv - 1;
                    if (bit_idx == 3'd7)
                        next_state = STOP;
                end
            end

            STOP: begin
                if (baud_done) begin
                    if (rx == 1'b1)
                        next_state = DONE;
                    else
                        next_state = ERR;
                end
            end

            DONE: next_state = IDLE; // auto-return; rx_done pulses 1 cycle
            ERR:  next_state = IDLE; // auto-return; rx_err pulses 1 cycle
        endcase
    end

    //-------------------------
    // FSM State register
    //-------------------------
    always @(posedge clk or negedge arst_n) begin
        if (!arst_n)
            state <= IDLE;
        else if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    //-------------------------
    // SIPO Shift Register
    //-------------------------
    reg [7:0] sipo;

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n)
            sipo <= 8'h00;
        else if (rst)
            sipo <= 8'h00;
        else if (state == DATA && sipo_en) begin
            sipo <= {rx, sipo[7:1]}; // shift LSB first
        end
    end

    //-------------------------
    // Outputs
    //-------------------------
    assign rx_busy = (state != IDLE)    ;
    assign rx_done = (state == DONE)    ;
    assign rx_err  = (state == ERR)     ;

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n)
            rx_data <= 8'h00;
        else if (rst)
            rx_data <= 8'h00;
        else if (state == DONE)
            rx_data <= sipo;
    end

    // Bit counter
    always @(posedge clk or negedge arst_n) begin
        if (!arst_n)
            bit_idx <= 0;
        else if (rst)
            bit_idx <= 0;
        else if (state == DATA && baud_done && sipo_en)
            bit_idx <= bit_idx + 1;
        else if (state == IDLE)
            bit_idx <= 0;
    end

endmodule
`default_nettype wire