//==============================================================================
//  Module      : axis_uart_tx_bridge
//  Description : AXI-Stream (8-bit) slave → UART TX bridge.
//                Accepts one AXI-S beat (8-bit TDATA) and transmits it as a
//                single UART byte.  TREADY is deasserted for the duration of
//                the transmission and reasserted once the stop bit completes.
//
//                UART idle state (tx=1) is restored on the first clock cycle
//                after reset via a one-cycle sync-rst pulse to uart_tx
//                (uart_tx async-resets tx to 0, which is not idle).
//
//  Parameters:
//    BAUDIV — clock cycles per baud period.  100 MHz / 115200 ≈ 868.
//
//  Dependencies: uart_tx (must be in the same compilation unit / filelist)
//==============================================================================

`default_nettype none

module axis_uart_tx_bridge #(
    parameter [31:0] BAUDIV = 32'd868   // clock cycles per baud period
) (
    input  wire       clk,        // system clock (must match BAUDIV)
    input  wire       arst_n,     // async reset, active low

    // AXI-Stream slave
    input  wire [7:0] s_tdata,
    input  wire       s_tvalid,
    output reg        s_tready,

    output wire       tx           // UART TX pin (connect to host RX)
);

    // -------------------------------------------------------------------------
    // Startup sync-reset: drives uart_tx rst=1 for the first active clock
    // cycle so that tx is forced to the idle level (1) after arst_n deasserts.
    // uart_tx async-resets tx to 0, which would look like a start bit.
    // -------------------------------------------------------------------------
    reg startup_done;
    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) startup_done <= 1'b0;
        else         startup_done <= 1'b1;
    end
    wire init_rst = ~startup_done;   // high for exactly the 1st active cycle

    // -------------------------------------------------------------------------
    // uart_tx instance
    // -------------------------------------------------------------------------
    reg  [7:0] tx_data_r;
    reg        tx_en;
    wire       tx_done;

    uart_tx u_utx (
        .clk    (clk),
        .arst_n (arst_n),
        .rst    (init_rst),      // one-shot startup reset → tx goes to 1
        .tx_en  (tx_en),
        .tx_data(tx_data_r),
        .baudiv (BAUDIV),
        .tx     (tx),
        .tx_busy(),
        .tx_done(tx_done)
    );

    // -------------------------------------------------------------------------
    // FSM
    //
    //  S_IDLE : TREADY=1; wait for TVALID.  On handshake, latch TDATA,
    //           assert tx_en, deassert TREADY, go to S_TX.
    //  S_TX   : TREADY=0; hold tx_en and tx_data_r stable until uart_tx
    //           signals tx_done (stop bit complete), then return to S_IDLE.
    // -------------------------------------------------------------------------
    localparam S_IDLE = 1'b0,
               S_TX   = 1'b1;

    reg fsm;

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            fsm       <= S_IDLE;
            tx_en     <= 1'b0;
            tx_data_r <= 8'h00;
            s_tready  <= 1'b0;   // held low until startup_done (init_rst clears)
        end else begin
            case (fsm)

                S_IDLE: begin
                    s_tready <= 1'b1;
                    if (s_tvalid) begin
                        tx_data_r <= s_tdata;
                        tx_en     <= 1'b1;
                        s_tready  <= 1'b0;
                        fsm       <= S_TX;
                    end
                end

                S_TX: begin
                    if (tx_done) begin
                        tx_en    <= 1'b0;
                        // s_tready re-asserted next cycle (S_IDLE default)
                        fsm      <= S_IDLE;
                    end
                end

                default: fsm <= S_IDLE;

            endcase
        end
    end

endmodule

`default_nettype wire
