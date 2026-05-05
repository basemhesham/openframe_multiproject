// TraceGuard-X ASIC — AUC Silicon Sprint
// Module : cmd_decoder
// Process: SKY130 Open PDK
// Authors: Omar Ahmed Fouad, Ahmed Tawfiq, Omar Ahmed Abdelaty
//
// RTL source — see docs/report/ for full module specification.

module cmd_decoder #(
    parameter MAX_STATES = 16 
) (
    input  wire        clk,
    input  wire        rst_n,

    // from UART transceiver
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    output reg         rx_ready,

    // to Control FSM
    output reg  [1:0]  mode_cmd,
    output reg         mode_cmd_valid,

    // to Pattern SRAM
    output reg  [8:0]  sram_addr,
    output reg  [7:0]  sram_wdata,
    output reg         sram_wr_en,
    input  wire [7:0]  sram_rdata,
    output reg         sram_rd_en,

    // to Score & Threshold unit
    output reg  [7:0]  threshold_reg,
    output reg         threshold_wr,

    // to Sliding Window
    output reg  [4:0]  window_size,
    output reg         window_size_wr,

    // to Output Register
    output reg  [7:0]  tx_data,
    output reg         tx_valid,
    input  wire        tx_ready,

    // chip lock interface
    output reg         lock_cmd,
    output reg  [15:0] pin_data,
    input  wire        lock_granted,

    // stream tokens
    output reg  [7:0]  stream_token,
    output reg         stream_valid,

    // result request output
    output reg         send_result_req,

    // incoming status for responses
    input  wire [7:0]  score_in,
    input  wire [1:0]  mode_in,
    input  wire [3:0]  flags_in,
    input  wire        overflow_wire
);

    wire _unused = &{1'b0, lock_granted};

    // Opcodes 
    localparam DEC_OP_SET_MODE       = 8'hA0;
    localparam DEC_OP_WRITE_PATTERN  = 8'hA1;
    localparam DEC_OP_DELETE_PATTERN = 8'hA2;
    localparam DEC_OP_READ_PATTERN   = 8'hA3;
    localparam DEC_OP_SET_THRESHOLD  = 8'hA4;
    localparam DEC_OP_SUBMIT_SEQ     = 8'hA5;
    localparam DEC_OP_SET_PIN        = 8'hA6;
    localparam DEC_OP_UNLOCK         = 8'hA7;
    localparam DEC_OP_SET_WINDOW     = 8'hA8;
    localparam DEC_OP_GET_STATUS     = 8'hA9;


    localparam DIR_BASE = 9'h000;
    localparam PAT_BASE = 9'h002; 

    localparam [3:0] CMD_S_IDLE    = 4'b0001, 
                     CMD_S_LENGTH  = 4'b0010, 
                     CMD_S_PAYLOAD = 4'b0100, 
                     CMD_S_EXEC    = 4'b1000;

    reg [3:0] state;
    reg [7:0] opcode;
    reg [5:0] len;
    reg [5:0] byte_cnt;
    reg [5:0] exec_cnt;
    reg       read_wait;
    reg [5:0] read_pat_len;
    reg [7:0] pbuf [0:32]; 
    reg       byte_consumed;
    reg       overflow_reg; 

    wire [8:0]  exec_cnt_calc   = {3'b0, exec_cnt} - 9'd2;
    wire [8:0]  target_dir_addr = DIR_BASE; 
    wire [8:0]  target_pat_addr = PAT_BASE + exec_cnt_calc;

    wire overflow_clr_cond = (state == CMD_S_EXEC) && (opcode == DEC_OP_SET_MODE) && (pbuf[0][1:0] == 2'b01);
    
    wire [5:0] len_minus_1 = len - 6'd1;
    wire [5:0] len_plus_1  = len + 6'd1;
    wire [5:0] exec_cnt_m1 = exec_cnt - 6'd1;
    wire [5:0] read_pat_len_plus_1 = read_pat_len + 6'd1;


    localparam [5:0] MAX_PAYLOAD     = MAX_STATES;     
    localparam [7:0] MAX_PATTERN_LEN = MAX_STATES - 1; 
    
    wire [5:0] max_allowed_payload = MAX_PAYLOAD;
    wire [7:0] capped_len_to_write = (len > max_allowed_payload) ? MAX_PATTERN_LEN : {2'b0, len_minus_1};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            overflow_reg <= 1'b0;
        else if (overflow_wire) 
            overflow_reg <= 1'b1;
        else if (overflow_clr_cond) 
            overflow_reg <= 1'b0;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {opcode, tx_data, stream_token, threshold_reg} <= 32'd0;
            {byte_cnt, exec_cnt, read_pat_len, len} <= 24'd0;
            {sram_addr, window_size} <= 14'd0;
            {sram_wdata, pin_data} <= 24'd0;
            {rx_ready, mode_cmd_valid, sram_wr_en, sram_rd_en, threshold_wr, window_size_wr, tx_valid, lock_cmd, stream_valid, send_result_req, byte_consumed, read_wait} <= 12'd0;
            state <= CMD_S_IDLE;
            mode_cmd <= 2'd0;
        end else begin
            {rx_ready, mode_cmd_valid, sram_wr_en, sram_rd_en, threshold_wr, window_size_wr, tx_valid, lock_cmd, stream_valid, send_result_req} <= 10'd0;

            if (!rx_valid) byte_consumed <= 1'b0;

            case (state)
                CMD_S_IDLE: begin
                    exec_cnt  <= 6'd0;
                    read_wait <= 1'b0;
                    tx_valid  <= 1'b0;
                    if (rx_valid && !byte_consumed) begin
                        rx_ready <= 1'b1;
                        byte_consumed <= 1'b1;
                        if (rx_data >= DEC_OP_SET_MODE && rx_data <= DEC_OP_GET_STATUS) begin
                            opcode <= rx_data;
                            state  <= CMD_S_LENGTH;
                        end else begin
                            stream_token <= rx_data;
                            stream_valid <= 1'b1;
                        end
                    end
                end

                CMD_S_LENGTH: begin
                    if (rx_valid && !byte_consumed) begin
                        rx_ready <= 1'b1;
                        byte_consumed <= 1'b1;
                        len      <= rx_data[5:0];
                        byte_cnt <= 6'd0;
                        if (rx_data == 8'd0) state <= CMD_S_EXEC;
                        else                 state <= CMD_S_PAYLOAD;
                    end
                end

                CMD_S_PAYLOAD: begin
                    if (rx_valid && !byte_consumed) begin
                        rx_ready <= 1'b1;
                        byte_consumed <= 1'b1;
                        
                        if (byte_cnt < 6'd33) begin
                            pbuf[byte_cnt] <= rx_data;
                        end
                        
                        byte_cnt <= byte_cnt + 1'b1;
                        if (byte_cnt + 1'b1 == len) state <= CMD_S_EXEC;
                    end
                end

                CMD_S_EXEC: begin
                    case (opcode)
                        DEC_OP_SET_MODE: begin
                            mode_cmd       <= pbuf[0][1:0];
                            mode_cmd_valid <= 1'b1;
                            state          <= CMD_S_IDLE;
                        end

                        DEC_OP_WRITE_PATTERN: begin
                            if (exec_cnt == 0) begin
                                sram_addr  <= target_dir_addr; 
                                sram_wdata <= 8'hFF;
                                sram_wr_en <= 1'b1;
                                exec_cnt   <= 6'd1;
                            end else if (exec_cnt == 1) begin
                                sram_addr  <= target_dir_addr + 9'd1; 
                                sram_wdata <= capped_len_to_write; 
                                sram_wr_en <= 1'b1;
                                exec_cnt   <= 6'd2;
                            end else begin
                                sram_addr  <= target_pat_addr; 
                                sram_wdata <= pbuf[exec_cnt_m1];
                                sram_wr_en <= 1'b1;
                                
                                if (exec_cnt == len_plus_1 || exec_cnt == max_allowed_payload + 1) state <= CMD_S_IDLE;
                                else                                                               exec_cnt <= exec_cnt + 1'b1;
                            end
                        end

                        DEC_OP_DELETE_PATTERN: begin
                            sram_addr  <= target_dir_addr; 
                            sram_wdata <= 8'h00; 
                            sram_wr_en <= 1'b1;
                            state      <= CMD_S_IDLE;
                        end

                        DEC_OP_SET_THRESHOLD: begin
                            threshold_reg <= pbuf[0];
                            threshold_wr  <= 1'b1;
                            state         <= CMD_S_IDLE;
                        end

                        DEC_OP_SET_WINDOW: begin
                            window_size    <= pbuf[0][4:0];
                            window_size_wr <= 1'b1;
                            state          <= CMD_S_IDLE;
                        end

                        DEC_OP_SET_PIN, DEC_OP_UNLOCK: begin
                            pin_data <= {pbuf[0], pbuf[1]};
                            lock_cmd <= 1'b1;
                            state    <= CMD_S_IDLE;
                        end

                        DEC_OP_GET_STATUS: begin
                            if (tx_ready && !tx_valid) begin
                                tx_valid <= 1'b1;
                                case (exec_cnt)
                                    0: tx_data <= 8'hB0;
                                    1: tx_data <= score_in;
                                    2: tx_data <= {6'b0, mode_in};
                                    3: tx_data <= {3'b0, overflow_reg, flags_in[3:0]};
                                    4: tx_data <= 8'h00;
                                    default: tx_data <= 8'h00;
                                endcase
                            end else if (tx_valid) begin
                                tx_valid <= 1'b0;
                                if (exec_cnt == 4) state <= CMD_S_IDLE;
                                else               exec_cnt <= exec_cnt + 1'b1;
                            end
                        end

                        DEC_OP_SUBMIT_SEQ: begin
                            stream_token <= pbuf[exec_cnt];
                            stream_valid <= 1'b1;
                            if (exec_cnt == len_minus_1) begin
                                if (tx_ready && !tx_valid) begin
                                    send_result_req <= 1'b1;
                                    tx_data         <= 8'hB1;
                                    tx_valid        <= 1'b1;
                                end else if (tx_valid) begin
                                    tx_valid <= 1'b0;
                                    state    <= CMD_S_IDLE;
                                end
                            end else begin
                                exec_cnt <= exec_cnt + 1'b1;
                            end
                        end

                        DEC_OP_READ_PATTERN: begin
                            if (!read_wait) begin
                                if (exec_cnt == 0)      sram_addr <= target_dir_addr; 
                                else if (exec_cnt == 1) sram_addr <= target_dir_addr + 9'd1; 
                                else                    sram_addr <= target_pat_addr; 
                                sram_rd_en <= 1'b1;
                                read_wait  <= 1'b1;
                            end else begin
                                if (!sram_rd_en) begin
                                    if (tx_ready && !tx_valid) begin
                                        tx_valid  <= 1'b1;
                                        tx_data   <= sram_rdata;
                                    end else if (tx_valid) begin
                                        tx_valid  <= 1'b0;
                                        read_wait <= 1'b0;
                                        if (exec_cnt == 6'd1) begin
                                            read_pat_len <= sram_rdata[5:0];
                                            exec_cnt     <= exec_cnt + 1'b1;
                                        end else if (exec_cnt == read_pat_len_plus_1) begin
                                            state <= CMD_S_IDLE;
                                        end else begin
                                            exec_cnt <= exec_cnt + 1'b1;
                                        end
                                    end
                                end
                            end
                        end

                        default: state <= CMD_S_IDLE;
                    endcase
                end
                default: state <= CMD_S_IDLE;
            endcase
        end
    end
endmodule
