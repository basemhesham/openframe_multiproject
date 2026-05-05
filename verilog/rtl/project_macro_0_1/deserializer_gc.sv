// =========================================================
// Module: deserializer_gc
// Purpose: Runtime-configurable UART deserializer with dynamic baud rate
// Derived from: deserializer.sv
// Change from parent: BAUD_RATE replaced with runtime input baud_div
// =========================================================

module deserializer_gc (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        rx,
    input  logic [15:0] baud_div,
    output logic [15:0] data_out,
    output logic        data_valid
);

    // LOW_BYTE_FIRST stays as localparam — not configurable at runtime
    localparam bit LOW_BYTE_FIRST = 1'b1;

    // Baud counter uses 16-bit fixed width (can hold up to 65535)
    localparam int unsigned BAUD_CNT_W = 16;

    typedef enum logic [1:0] {
        IDLE,
        START,
        DATA,
        STOP
    } uart_state_t;

    uart_state_t               state_q;
    logic [BAUD_CNT_W-1:0]     baud_cnt_q;
    logic [2:0]                bit_idx_q;
    logic [7:0]                rx_byte_q;
    logic [7:0]                first_byte_q;
    logic                      have_first_byte_q;
    logic                      rx_meta_q;
    logic                      rx_sync_q;
    logic                      rx_sync_d_q;
    logic                      rx_fall;
    logic [BAUD_CNT_W-1:0]     half_baud_div;

    assign rx_fall       = rx_sync_d_q && !rx_sync_q;
    assign half_baud_div = baud_div >> 1;

    // Synchronize the asynchronous UART input before edge detection and sampling.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta_q   <= 1'b1;
            rx_sync_q   <= 1'b1;
            rx_sync_d_q <= 1'b1;
        end else begin
            rx_meta_q   <= rx;
            rx_sync_q   <= rx_meta_q;
            rx_sync_d_q <= rx_sync_q;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q            <= IDLE;
            baud_cnt_q         <= '0;
            bit_idx_q          <= '0;
            rx_byte_q          <= '0;
            first_byte_q       <= '0;
            have_first_byte_q  <= 1'b0;
            data_out           <= '0;
            data_valid         <= 1'b0;
        end else begin
            data_valid <= 1'b0;

            unique case (state_q)
                IDLE: begin
                    baud_cnt_q <= '0;
                    bit_idx_q  <= '0;

                    if (rx_fall) begin
                        state_q    <= START;
                        rx_byte_q  <= '0;
                    end
                end

                START: begin
                    if (baud_cnt_q == half_baud_div - 1) begin
                        baud_cnt_q <= '0;

                        // Re-check the line near the middle of the start bit to reject glitches.
                        if (!rx_sync_q) begin
                            state_q   <= DATA;
                            bit_idx_q <= '0;
                        end else begin
                            state_q <= IDLE;
                        end
                    end else begin
                        baud_cnt_q <= baud_cnt_q + 1'b1;
                    end
                end

                DATA: begin
                    if (baud_cnt_q == baud_div - 1) begin
                        baud_cnt_q            <= '0;
                        rx_byte_q[bit_idx_q] <= rx_sync_q;

                        if (bit_idx_q == 3'd7) begin
                            state_q <= STOP;
                        end else begin
                            bit_idx_q <= bit_idx_q + 1'b1;
                        end
                    end else begin
                        baud_cnt_q <= baud_cnt_q + 1'b1;
                    end
                end

                STOP: begin
                    if (baud_cnt_q == baud_div - 1) begin
                        state_q    <= IDLE;
                        baud_cnt_q <= '0;

                        if (rx_sync_q) begin
                            if (!have_first_byte_q) begin
                                first_byte_q      <= rx_byte_q;
                                have_first_byte_q <= 1'b1;
                            end else begin
                                if (LOW_BYTE_FIRST) begin
                                    data_out <= {rx_byte_q, first_byte_q};
                                end else begin
                                    data_out <= {first_byte_q, rx_byte_q};
                                end

                                have_first_byte_q <= 1'b0;
                                data_valid        <= 1'b1;
                            end
                        end else begin
                            // Drop the partial word on framing error to preserve byte alignment.
                            have_first_byte_q <= 1'b0;
                        end
                    end else begin
                        baud_cnt_q <= baud_cnt_q + 1'b1;
                    end
                end

                default: begin
                    state_q <= IDLE;
                end
            endcase
        end
    end

endmodule
