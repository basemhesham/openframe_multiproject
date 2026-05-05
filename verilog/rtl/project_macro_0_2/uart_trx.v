// TraceGuard-X ASIC — AUC Silicon Sprint
// Module : uart_trx
// Process: SKY130 Open PDK
// Authors: Omar Ahmed Fouad, Ahmed Tawfiq, Omar Ahmed Abdelaty
//
// RTL source — see docs/report/ for full module specification.

module uart_trx #(
    parameter TRX_CLK_FREQ   = 25_000_000,
    parameter TRX_BAUD_RATE  = 115_200,
    parameter TRX_FIFO_DEPTH = 16
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_rx,
    output reg        uart_tx,
    output wire [7:0] rx_data,
    output wire       rx_valid,
    input  wire       rx_ready,
    input  wire [7:0] tx_data,
    input  wire       tx_valid,
    output wire       tx_ready,
    output reg        rx_overflow,
    output reg        frame_error,
    output wire       tx_busy
);

    localparam CLKS_PER_BIT = TRX_CLK_FREQ / TRX_BAUD_RATE;
    
    localparam [3:0] RX_S_IDLE = 4'b0001, RX_S_START = 4'b0010, RX_S_DATA = 4'b0100, RX_S_STOP = 4'b1000;
    localparam [3:0] TX_S_IDLE = 4'b0001, TX_S_START = 4'b0010, TX_S_DATA = 4'b0100, TX_S_STOP = 4'b1000;


    reg [7:0] rx_fifo [0:TRX_FIFO_DEPTH-1];
    reg [4:0] rx_wr_ptr, rx_rd_ptr;
    wire      rx_empty = (rx_wr_ptr == rx_rd_ptr);
    wire      rx_full  = (rx_wr_ptr[3:0] == rx_rd_ptr[3:0]) && (rx_wr_ptr[4] != rx_rd_ptr[4]);

    reg [7:0] tx_fifo [0:TRX_FIFO_DEPTH-1];
    reg [4:0] tx_wr_ptr, tx_rd_ptr;
    wire      tx_empty = (tx_wr_ptr == tx_rd_ptr);
    wire      tx_full  = (tx_wr_ptr[3:0] == tx_rd_ptr[3:0]) && (tx_wr_ptr[4] != tx_rd_ptr[4]);

    assign rx_data  = rx_fifo[rx_rd_ptr[3:0]]; 
    assign rx_valid = !rx_empty;
    assign tx_ready = !tx_full;

    integer i, j;


    reg rx_sync1, rx_sync2, rx_sync3;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) {rx_sync3, rx_sync2, rx_sync1} <= 3'b111;
        else        {rx_sync3, rx_sync2, rx_sync1} <= {rx_sync2, rx_sync1, uart_rx};
    end


    reg [3:0]  rx_state;
    reg [15:0] rx_clk_cnt;
    reg [2:0]  rx_bit_cnt;
    reg [7:0]  rx_shift;
    reg        rx_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state    <= RX_S_IDLE;
            {rx_clk_cnt, rx_bit_cnt, rx_shift} <= 27'd0;
            {rx_done, frame_error} <= 2'd0;
        end else begin
            {rx_done, frame_error} <= 2'd0;
            
            case (rx_state)
                RX_S_IDLE: begin
                    rx_clk_cnt <= 16'd0;
                    rx_bit_cnt <= 3'd0;
                    if (rx_sync3 == 1'b0) rx_state <= RX_S_START;
                end
                RX_S_START: begin
                    if (rx_clk_cnt == (CLKS_PER_BIT / 2)) begin
                        rx_clk_cnt <= 16'd0;
                        if (rx_sync3 == 1'b0) rx_state <= RX_S_DATA; 
                        else                  rx_state <= RX_S_IDLE;
                    end else rx_clk_cnt <= rx_clk_cnt + 1'b1;
                end
                RX_S_DATA: begin
                    if (rx_clk_cnt == CLKS_PER_BIT - 1) begin
                        rx_clk_cnt <= 16'd0;
                        rx_shift   <= {rx_sync3, rx_shift[7:1]}; 
                        if (rx_bit_cnt == 3'd7) rx_state <= RX_S_STOP;
                        else                    rx_bit_cnt <= rx_bit_cnt + 1'b1;
                    end else rx_clk_cnt <= rx_clk_cnt + 1'b1;
                end
                RX_S_STOP: begin
                    if (rx_clk_cnt == CLKS_PER_BIT - 1) begin
                        rx_clk_cnt <= 16'd0;
                        if (rx_sync3 == 1'b1) rx_done     <= 1'b1;
                        else                  frame_error <= 1'b1;
                        rx_state <= RX_S_IDLE;
                    end else rx_clk_cnt <= rx_clk_cnt + 1'b1;
                end
                default: rx_state <= RX_S_IDLE;
            endcase
        end
    end

    // RX FIFO
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {rx_wr_ptr, rx_rd_ptr} <= 10'd0;
            rx_overflow <= 1'b0;
            for(i=0; i<TRX_FIFO_DEPTH; i=i+1) rx_fifo[i] <= 8'd0;
        end else begin
            rx_overflow <= 1'b0;
            if (rx_done) begin
                if (!rx_full) begin
                    rx_fifo[rx_wr_ptr[3:0]] <= rx_shift;
                    rx_wr_ptr               <= rx_wr_ptr + 1'b1;
                end else rx_overflow <= 1'b1;
            end
            if (rx_ready && !rx_empty) rx_rd_ptr <= rx_rd_ptr + 1'b1;
        end
    end


    reg [3:0]  tx_state;
    reg [15:0] tx_clk_cnt;
    reg [2:0]  tx_bit_cnt;
    reg [7:0]  tx_shift;
    reg        tx_pop;

    assign tx_busy = (tx_state != TX_S_IDLE) || !tx_empty;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state   <= TX_S_IDLE;
            {tx_clk_cnt, tx_bit_cnt, tx_shift} <= 27'd0;
            uart_tx    <= 1'b1;
            tx_pop     <= 1'b0;
        end else begin
            tx_pop <= 1'b0;
            case (tx_state)
                TX_S_IDLE: begin
                    uart_tx    <= 1'b1;
                    tx_clk_cnt <= 16'd0;
                    tx_bit_cnt <= 3'd0;
                    if (!tx_empty) begin
                        tx_shift <= tx_fifo[tx_rd_ptr[3:0]];
                        tx_pop   <= 1'b1;
                        tx_state <= TX_S_START;
                    end
                end
                TX_S_START: begin
                    uart_tx <= 1'b0;
                    if (tx_clk_cnt == CLKS_PER_BIT - 1) begin
                        tx_clk_cnt <= 16'd0;
                        tx_state   <= TX_S_DATA;
                    end else tx_clk_cnt <= tx_clk_cnt + 1'b1;
                end
                TX_S_DATA: begin
                    uart_tx <= tx_shift[0];
                    if (tx_clk_cnt == CLKS_PER_BIT - 1) begin
                        tx_clk_cnt <= 16'd0;
                        tx_shift   <= {1'b0, tx_shift[7:1]};
                        if (tx_bit_cnt == 3'd7) tx_state <= TX_S_STOP;
                        else                    tx_bit_cnt <= tx_bit_cnt + 1'b1;
                    end else tx_clk_cnt <= tx_clk_cnt + 1'b1;
                end
                TX_S_STOP: begin
                    uart_tx <= 1'b1;
                    if (tx_clk_cnt == CLKS_PER_BIT - 1) begin
                        tx_clk_cnt <= 16'd0;
                        tx_state   <= TX_S_IDLE;
                    end else tx_clk_cnt <= tx_clk_cnt + 1'b1;
                end
                default: tx_state <= TX_S_IDLE;
            endcase
        end
    end

    // TX FIFO
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {tx_wr_ptr, tx_rd_ptr} <= 10'd0;
            for(j=0; j<TRX_FIFO_DEPTH; j=j+1) tx_fifo[j] <= 8'd0;
        end else begin
            if (tx_valid && !tx_full) begin
                tx_fifo[tx_wr_ptr[3:0]] <= tx_data;
                tx_wr_ptr               <= tx_wr_ptr + 1'b1;
            end
            if (tx_pop) tx_rd_ptr <= tx_rd_ptr + 1'b1;
        end
    end

endmodule
