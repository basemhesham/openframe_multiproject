module U_Butterfly_Unit #(
    parameter DATA_WIDTH = 12
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire mode,               
    input  wire [DATA_WIDTH-1:0] q, 
    input  wire [DATA_WIDTH-1:0] U_in,
    input  wire [DATA_WIDTH-1:0] V_in,
    input  wire [DATA_WIDTH-1:0] twiddle, 
    
    output reg  [DATA_WIDTH-1:0] U_out,
    output reg  [DATA_WIDTH-1:0] V_out,
    output reg  done
);

    localparam [2:0] IDLE     = 3'd0,
                     OP1_MULT = 3'd1,    
                     OP2_ADD  = 3'd2,     
                     OP3_SUB  = 3'd3,     
                     FINISH   = 3'd4;

    reg [2:0] state, next_state;

    reg [DATA_WIDTH-1:0] t;         
    reg [DATA_WIDTH-1:0] t2;        
    reg [DATA_WIDTH-1:0] shift_reg; 
    reg [3:0]            iter_cnt;  

    wire [DATA_WIDTH:0] temp_add;
    wire [DATA_WIDTH:0] shifted_t2;
    
    assign temp_add = t + t2;
    assign shifted_t2 = {t2, 1'b0};

    wire [DATA_WIDTH:0]   mas_add_res;
    wire [DATA_WIDTH+1:0] mas_sub_res_safe; 
    
    assign mas_add_res = U_in + t;
    assign mas_sub_res_safe = U_in + q - t;  

    wire [DATA_WIDTH-1:0] add_mod_q, sub_mod_q;
    wire [DATA_WIDTH:0]   add_div2, sub_div2;

    assign add_mod_q = (mas_add_res >= q) ? (mas_add_res - q) : mas_add_res[DATA_WIDTH-1:0];
    assign sub_mod_q = (mas_sub_res_safe >= q) ? (mas_sub_res_safe - q) : mas_sub_res_safe[DATA_WIDTH-1:0];

    assign add_div2 = (add_mod_q[0]) ? (add_mod_q + q) >> 1 : add_mod_q >> 1;
    assign sub_div2 = (sub_mod_q[0]) ? (sub_mod_q + q) >> 1 : sub_mod_q >> 1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            t <= 0; 
            t2 <= 0;
            shift_reg <= 0; 
            iter_cnt <= 0;
            U_out <= 0; 
            V_out <= 0;
            done <= 0;
        end else begin
            state <= next_state;
            
            case (state)
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        shift_reg <= twiddle;
                        t2 <= V_in;
                        t  <= 0;
                        iter_cnt <= 0;
                    end
                end

                OP1_MULT: begin
                    if (shift_reg[0]) begin
                        t <= (temp_add >= q) ? (temp_add - q) : temp_add[DATA_WIDTH-1:0];
                    end
                    
                    shift_reg <= shift_reg >> 1;
                    t2 <= (shifted_t2 >= q) ? (shifted_t2 - q) : shifted_t2[DATA_WIDTH-1:0];
                    iter_cnt <= iter_cnt + 1;
                end

                OP2_ADD: begin
                    if (mode == 1'b0) U_out <= add_mod_q;
                    else              U_out <= add_div2[DATA_WIDTH-1:0];
                end

                OP3_SUB: begin
                    if (mode == 1'b0) V_out <= sub_mod_q;
                    else              V_out <= sub_div2[DATA_WIDTH-1:0];
                end

                FINISH: begin
                    done <= 1'b1;
                end
            endcase
        end
    end

    always @* begin
        next_state = state;
        case (state)
            IDLE:     if (start) next_state = OP1_MULT;
            OP1_MULT: if (iter_cnt == DATA_WIDTH-1) next_state = OP2_ADD;
            OP2_ADD:  next_state = OP3_SUB;
            OP3_SUB:  next_state = FINISH;
            FINISH:   next_state = IDLE;
            default:  next_state = IDLE;
        endcase
    end

endmodule