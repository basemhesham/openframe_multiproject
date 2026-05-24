module NTT_Control_Unit #(
    parameter ADDR_WIDTH = 8
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire mode,     // Mode is required to determine traversal direction
    input  wire ubu_done,

    output reg  [ADDR_WIDTH-1:0] ram_addr_a,
    output reg  [ADDR_WIDTH-1:0] ram_addr_b,
    output reg  ram_we,
    output reg  ubu_start,
    output reg  [6:0] twiddle_addr,
    output reg  done,
    output wire busy
);

    localparam [2:0] IDLE          = 3'd0,
                     READ_RAM      = 3'd1,
                     WAIT_RAM_READ = 3'd2,
                     WAIT_UBU      = 3'd3,
                     WRITE_RAM     = 3'd4,
                     UPDATE_IDX    = 3'd5,
                     DONE_ST       = 3'd6;

    reg [2:0] state, next_state;
    reg [3:0] stage;
    reg [8:0] len;       // 9-bit to safely store 128 and left-shift to 256
    reg [8:0] start_idx; // 9-bit to prevent overflow during additions
    reg [8:0] offset;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            stage        <= 4'd0;
            len          <= 9'd128;
            start_idx    <= 9'd0;
            offset       <= 9'd0;
            twiddle_addr <= 7'd0;
            ram_we       <= 1'b0;
            ubu_start    <= 1'b0;
            done         <= 1'b0;
            ram_addr_a   <= {ADDR_WIDTH{1'b0}};
            ram_addr_b   <= {ADDR_WIDTH{1'b0}};
        end else begin
            state <= next_state;
            case (state)
                IDLE: begin
                    if (start) begin
                        stage        <= 4'd0;
                        // Mode 0: CT (128 -> 1), Mode 1: GS (2 -> 128)
                        len          <= (mode == 1'b0) ? 9'd128 : 9'd2; 
                        start_idx    <= 9'd0;
                        offset       <= 9'd0;
                        twiddle_addr <= 7'd0;
                        done         <= 1'b0;
                    end
                end
                READ_RAM: begin
                    ram_we     <= 1'b0;
                    ubu_start  <= 1'b0;
                    ram_addr_a <= start_idx[ADDR_WIDTH-1:0] + offset[ADDR_WIDTH-1:0];
                    ram_addr_b <= start_idx[ADDR_WIDTH-1:0] + offset[ADDR_WIDTH-1:0] + len[ADDR_WIDTH-1:0];
                end
                WAIT_RAM_READ: begin
                    ubu_start <= 1'b1;
                end
                WAIT_UBU: begin
                    ubu_start <= 1'b0;
                end
                WRITE_RAM: begin
                    ram_we     <= 1'b1;
                    ram_addr_a <= start_idx[ADDR_WIDTH-1:0] + offset[ADDR_WIDTH-1:0];
                    ram_addr_b <= start_idx[ADDR_WIDTH-1:0] + offset[ADDR_WIDTH-1:0] + len[ADDR_WIDTH-1:0];
                end
                UPDATE_IDX: begin
                    ram_we <= 1'b0;
                    if (offset + 9'd1 == len) begin
                        offset       <= 9'd0;
                        twiddle_addr <= twiddle_addr + 7'd1;
                        if (start_idx + (len << 1) >= 9'd256) begin
                            start_idx <= 9'd0;
                            stage     <= stage + 4'd1;
                            // Reverse length updates for INTT
                            len       <= (mode == 1'b0) ? (len >> 1) : (len << 1); 
                        end else begin
                            start_idx <= start_idx + (len << 1);
                        end
                    end else begin
                        offset <= offset + 9'd1;
                    end
                end
                DONE_ST: begin
                    done <= 1'b1;
                end
                default: begin
                    done <= 1'b0;
                end
            endcase
        end
    end

    always @* begin
        next_state = state;
        case (state)
            IDLE:          if (start) next_state = READ_RAM;
            READ_RAM:      if (stage == 4'd7) next_state = DONE_ST; else next_state = WAIT_RAM_READ;
            WAIT_RAM_READ: next_state = WAIT_UBU;
            WAIT_UBU:      if (ubu_done) next_state = WRITE_RAM;
            WRITE_RAM:     next_state = UPDATE_IDX;
            UPDATE_IDX:    if (stage == 4'd7) next_state = DONE_ST; else next_state = READ_RAM;
            DONE_ST:       next_state = IDLE;
            default:       next_state = IDLE;
        endcase
    end

    assign busy = (state != IDLE);

endmodule