//==============================================================================
//  Module      : uart_rx_axis_bridge
//  Description : UART RX → AXI-Stream (16-bit) bridge.
//                Receives two consecutive UART bytes and presents them as a
//                single 16-bit AXI-S beat.  Byte ordering: first byte
//                received occupies TDATA[7:0] (LSB), second byte occupies
//                TDATA[15:8] (MSB).
//
//                TVALID is asserted once both bytes have been assembled.
//                TDATA and TVALID are held stable until TREADY is sampled
//                high (AXI-S handshake).
//
//  Parameters:
//    BAUDIV — clock cycles per baud period.  100 MHz / 115200 ≈ 868.
//
//  Dependencies: uart_rx (must be in the same compilation unit / filelist)
//==============================================================================

`default_nettype none

module uart_rx_axis_bridge #(
    parameter [31:0] BAUDIV = 32'd868   // clock cycles per baud period
) (
    input  wire        clk,        // system clock (must match BAUDIV)
    input  wire        arst_n,     // async reset, active low

    input  wire        rx,         // UART RX pin (from host TX)

    // AXI-Stream master
    output reg  [15:0] m_tdata,
    output reg         m_tvalid,
    input  wire        m_tready
);

    // -------------------------------------------------------------------------
    // 2-FF metastability synchroniser on the RX pin
    // -------------------------------------------------------------------------
    reg rx_r, rx_rr;
    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            rx_r  <= 1'b1;
            rx_rr <= 1'b1;
        end else begin
            rx_r  <= rx;
            rx_rr <= rx_r;
        end
    end

    // -------------------------------------------------------------------------
    // uart_rx instance
    // -------------------------------------------------------------------------
    wire       urx_done;
    wire       urx_err;
    wire [7:0] urx_data;

    uart_rx u_urx (
        .clk    (clk),
        .arst_n (arst_n),
        .rst    (1'b0),
        .rx_en  (1'b1),
        .baudiv (BAUDIV),
        .rx     (rx_rr),
        .rx_busy(),
        .rx_done(urx_done),
        .rx_err (urx_err),
        .rx_data(urx_data)
    );

    // -------------------------------------------------------------------------
    // Packet-assembly FSM
    //
    //  S_IDLE  : wait for first UART byte  → stored as TDATA[7:0]
    //  S_BYTE1 : wait for second UART byte → stored as TDATA[15:8]
    //  S_VALID : hold TVALID/TDATA until the downstream slave asserts TREADY
    // -------------------------------------------------------------------------
    localparam [1:0]
        S_IDLE  = 2'd0,
        S_BYTE1 = 2'd1,
        S_VALID = 2'd2;

    reg [1:0] fsm;
    reg [7:0] byte0;

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            fsm      <= S_IDLE;
            byte0    <= 8'h00;
            m_tdata  <= 16'h0000;
            m_tvalid <= 1'b0;
        end else begin
            case (fsm)

                // Wait for byte 0 (becomes TDATA[7:0]).
                // uart_rx auto-returns to IDLE on framing error, so urx_err
                // just means we stay here and wait for the next start bit.
                S_IDLE: begin
                    m_tvalid <= 1'b0;
                    if (urx_done) begin
                        byte0 <= urx_data;
                        fsm   <= S_BYTE1;
                    end
                end

                // Wait for byte 1 (becomes TDATA[15:8]).
                S_BYTE1: begin
                    if (urx_done) begin
                        m_tdata  <= {byte0 , urx_data};  // MSB first in concat
                        m_tvalid <= 1'b1;
                        fsm      <= S_VALID;
                    end else if (urx_err) begin
                        // Discard partial packet; uart_rx already back in IDLE
                        fsm <= S_IDLE;
                    end
                end

                // Hold TVALID/TDATA stable until handshake completes.
                S_VALID: begin
                    if (m_tready) begin
                        m_tvalid <= 1'b0;
                        fsm      <= S_IDLE;
                    end
                end

                default: fsm <= S_IDLE;

            endcase
        end
    end

endmodule

`default_nettype wire
