module NTT_Control_Unit #(
    parameter ADDR_WIDTH = 8
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,
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
    reg [ADDR_WIDTH-1:0] len, start_idx, offset;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            stage <= 0; 
            len <= 128; 
            start_idx <= 0; 
            offset <= 0; 
            twiddle_addr <= 0;
            ram_we <= 0; 
            ubu_start <= 0; 
            done <= 0;
            ram_addr_a <= 0;
            ram_addr_b <= 0;
        end else begin
            state <= next_state;
            case (state)
                IDLE: begin
                    if (start) begin
                        stage <= 0; 
                        len <= 128; 
                        start_idx <= 0; 
                        offset <= 0; 
                        twiddle_addr <= 0; 
                        done <= 0;
                    end
                end
                READ_RAM: begin
                    ram_we <= 0; 
                    ubu_start <= 0;
                    ram_addr_a <= start_idx + offset;
                    ram_addr_b <= start_idx + offset + len;
                end
                WAIT_RAM_READ: ubu_start <= 1'b1; 
                WAIT_UBU:      ubu_start <= 1'b0;
                WRITE_RAM: begin
                    ram_we <= 1'b1;
                    ram_addr_a <= start_idx + offset;
                    ram_addr_b <= start_idx + offset + len;
                end
                UPDATE_IDX: begin
                    ram_we <= 0;
                    if (offset + 1 == len) begin 
                        offset <= 0;
                        twiddle_addr <= twiddle_addr + 1;
                        if (start_idx + (len << 1) >= 256) begin
                            start_idx <= 0; 
                            stage <= stage + 1; 
                            len <= len >> 1;
                        end else begin
                            start_idx <= start_idx + (len << 1);
                        end
                    end else begin
                        offset <= offset + 1;
                    end
                end
                DONE_ST: done <= 1'b1;
            endcase
        end
    end

    always @* begin
        next_state = state;
        case (state)
            IDLE:          if (start) next_state = READ_RAM;
            READ_RAM:      if (stage == 7) next_state = DONE_ST; else next_state = WAIT_RAM_READ;
            WAIT_RAM_READ: next_state = WAIT_UBU;
            WAIT_UBU:      if (ubu_done) next_state = WRITE_RAM;
            WRITE_RAM:     next_state = UPDATE_IDX;
            UPDATE_IDX:    if (stage == 7) next_state = DONE_ST; else next_state = READ_RAM;
            DONE_ST:       next_state = IDLE;
            default:       next_state = IDLE;
        endcase
    end

    assign busy = (state != IDLE);

endmodule