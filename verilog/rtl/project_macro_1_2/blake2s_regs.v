`default_nettype none
`timescale 1ns / 1ps

// OpenFrame SPI register file for single-block BLAKE2s-256 (see `blake2s_full_guide.md` Phase 6–8).
module blake2s_regs (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        cs,
    input  wire        we,
    input  wire [7:0]  address,
    input  wire [31:0] write_data,
    output reg  [31:0] read_data
);

    // -------------------------------------------------------------------------
    // Hash core (streaming byte interface)
    // -------------------------------------------------------------------------
    wire        ready_v_o;
    wire        h_v_o;
    wire [7:0]  h_o;

    wire        data_v_i;
    wire [5:0]  data_idx_i;
    wire [7:0]  data_i;
    wire        block_first_i;
    wire        block_last_i;

    blake2s_hash256 u_hash (
        .clk            (clk),
        .nreset         (reset_n),
        .kk_i           (6'd0),
        .nn_i           (6'd32),
        .ll_i           (64'd64),
        .block_first_i  (block_first_i),
        .block_last_i   (block_last_i),
        .slow_output_i  (1'b0),
        .data_v_i       (data_v_i),
        .data_idx_i     (data_idx_i),
        .data_i         (data_i),
        .ready_v_o      (ready_v_o),
        .h_v_o          (h_v_o),
        .h_o            (h_o)
    );

    // -------------------------------------------------------------------------
    // Message block (16 words) and digest (8 words)
    // -------------------------------------------------------------------------
    reg [31:0] msg_q[0:15];
    reg [31:0] digest_q[0:7];

    reg        busy_q;
    reg        done_q;
    reg        hash_capture_armed_q;

    // FSM: IDLE -> SEND_BLOCK -> CAPTURE_HASH -> IDLE (done=1)
    localparam [1:0] ST_IDLE        = 2'd0;
    localparam [1:0] ST_SEND_BLOCK  = 2'd1;
    localparam [1:0] ST_CAPTURE_HASH = 2'd2;

    reg [1:0] state_q;

    reg [5:0] tx_byte_idx_q;
    reg [5:0] rx_byte_idx_q;
    reg [7:0] out_byte_q[0:31];

    wire [3:0] tx_word_sel = tx_byte_idx_q[5:2];
    wire [1:0] tx_byte_sel = tx_byte_idx_q[1:0];
    wire [31:0] tx_word    = msg_q[tx_word_sel];
    reg  [7:0]  tx_byte;

    always @(*) begin
        case (tx_byte_sel)
            2'd0: tx_byte = tx_word[7:0];
            2'd1: tx_byte = tx_word[15:8];
            2'd2: tx_byte = tx_word[23:16];
            default: tx_byte = tx_word[31:24];
        endcase
    end

    wire feed_fire = (state_q == ST_SEND_BLOCK) && ready_v_o;

    assign data_v_i       = feed_fire;
    assign data_idx_i     = tx_byte_idx_q;
    assign data_i         = tx_byte;
    // The upstream core latches block_first_i across the whole input phase,
    // so keep it asserted for this fixed single-block wrapper.
    assign block_first_i  = 1'b1;
    assign block_last_i   = (tx_byte_idx_q == 6'd63);

    // Word index 0..7 for aligned digest addresses 0x50..0x6C
    /* verilator lint_off WIDTHTRUNC */
    wire [2:0] digest_word_sel = address[7:2] - 5'd20;
    /* verilator lint_on WIDTHTRUNC */

    integer ri;
    always @(posedge clk) begin
        if (!reset_n) begin
            read_data     <= 32'd0;
            busy_q        <= 1'b0;
            done_q        <= 1'b0;
            hash_capture_armed_q <= 1'b0;
            state_q       <= ST_IDLE;
            tx_byte_idx_q <= 6'd0;
            rx_byte_idx_q <= 6'd0;
            for (ri = 0; ri < 16; ri = ri + 1) begin
                msg_q[ri] <= 32'd0;
            end
            for (ri = 0; ri < 8; ri = ri + 1) begin
                digest_q[ri] <= 32'd0;
            end
            for (ri = 0; ri < 32; ri = ri + 1) begin
                out_byte_q[ri] <= 8'd0;
            end
        end else begin
            // SPI register writes
            if (cs && we) begin
                if ((address < 8'h40) && (address[1:0] == 2'b00)) begin
                    if (!busy_q) begin
                        msg_q[address[5:2]] <= write_data;
                    end
                end else if (address == 8'h40) begin
                    if (write_data[0] && !busy_q) begin
                        done_q        <= 1'b0;
                        busy_q        <= 1'b1;
                        hash_capture_armed_q <= 1'b0;
                        tx_byte_idx_q <= 6'd0;
                        rx_byte_idx_q <= 6'd0;
                        state_q       <= ST_SEND_BLOCK;
                    end
                end
            end

            // Stream 64 B into the core (one byte per cycle while ready)
            if (feed_fire) begin
                if (tx_byte_idx_q == 6'd63) begin
                    state_q <= ST_CAPTURE_HASH;
                end else begin
                    tx_byte_idx_q <= tx_byte_idx_q + 6'd1;
                end
            end

            // The upstream core asserts h_v_o one cycle early, so arm on the
            // first pulse and start storing on the first byte-valid S_RES beat.
            if (state_q == ST_CAPTURE_HASH && h_v_o && (rx_byte_idx_q < 6'd32)) begin
                if (!hash_capture_armed_q) begin
                    hash_capture_armed_q <= 1'b1;
                end else begin
                    if (rx_byte_idx_q == 6'd31) begin
                        digest_q[0] <= {
                            out_byte_q[3], out_byte_q[2], out_byte_q[1], out_byte_q[0]
                        };
                        digest_q[1] <= {
                            out_byte_q[7], out_byte_q[6], out_byte_q[5], out_byte_q[4]
                        };
                        digest_q[2] <= {
                            out_byte_q[11], out_byte_q[10], out_byte_q[9], out_byte_q[8]
                        };
                        digest_q[3] <= {
                            out_byte_q[15], out_byte_q[14], out_byte_q[13], out_byte_q[12]
                        };
                        digest_q[4] <= {
                            out_byte_q[19], out_byte_q[18], out_byte_q[17], out_byte_q[16]
                        };
                        digest_q[5] <= {
                            out_byte_q[23], out_byte_q[22], out_byte_q[21], out_byte_q[20]
                        };
                        digest_q[6] <= {
                            out_byte_q[27], out_byte_q[26], out_byte_q[25], out_byte_q[24]
                        };
                        digest_q[7] <= {
                            h_o, out_byte_q[30], out_byte_q[29], out_byte_q[28]
                        };
                        busy_q  <= 1'b0;
                        done_q  <= 1'b1;
                        state_q <= ST_IDLE;
                    end else begin
                        out_byte_q[rx_byte_idx_q[4:0]] <= h_o;
                        rx_byte_idx_q <= rx_byte_idx_q + 6'd1;
                    end
                end
            end

            // SPI register reads (synchronous)
            if (cs && !we) begin
                if (address == 8'h41) begin
                    read_data <= {30'd0, done_q, busy_q};
                end else if ((address >= 8'h50) && (address <= 8'h6C) && (address[1:0] == 2'b00)) begin
                    read_data <= digest_q[digest_word_sel];
                end else if ((address < 8'h40) && (address[1:0] == 2'b00)) begin
                    read_data <= msg_q[address[5:2]];
                end else begin
                    read_data <= 32'd0;
                end
            end
        end
    end

endmodule
