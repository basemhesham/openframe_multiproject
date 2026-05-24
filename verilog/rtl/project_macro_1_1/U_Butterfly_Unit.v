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

    wire [DATA_WIDTH:0] u_plus_v  = {1'b0, U_in} + {1'b0, V_in};
    wire [DATA_WIDTH:0] u_minus_v = {1'b0, U_in} + {1'b0, q} - {1'b0, V_in};

    wire [DATA_WIDTH-1:0] sum_mod  = (u_plus_v >= {1'b0, q}) ? (u_plus_v - {1'b0, q}) : u_plus_v;
    wire [DATA_WIDTH-1:0] diff_mod = (u_minus_v >= {1'b0, q}) ? (u_minus_v - {1'b0, q}) : u_minus_v;

    wire [DATA_WIDTH:0] sum_mod_odd  = {1'b0, sum_mod} + {1'b0, q};
    wire [DATA_WIDTH:0] diff_mod_odd = {1'b0, diff_mod} + {1'b0, q};

    wire [DATA_WIDTH-1:0] add_div2 = sum_mod[0]  ? sum_mod_odd[DATA_WIDTH:1]  : sum_mod[DATA_WIDTH-1:1];
    wire [DATA_WIDTH-1:0] sub_div2 = diff_mod[0] ? diff_mod_odd[DATA_WIDTH:1] : diff_mod[DATA_WIDTH-1:1];

    wire [DATA_WIDTH:0] temp_add   = {1'b0, t} + {1'b0, t2};
    wire [DATA_WIDTH:0] shifted_t2 = {t2, 1'b0};

    wire [DATA_WIDTH:0] u_plus_t  = {1'b0, U_in} + {1'b0, t};
    wire [DATA_WIDTH:0] u_minus_t = {1'b0, U_in} + {1'b0, q} - {1'b0, t};

    wire [DATA_WIDTH-1:0] ct_u_out = (u_plus_t >= {1'b0, q}) ? (u_plus_t - {1'b0, q}) : u_plus_t;
    wire [DATA_WIDTH-1:0] ct_v_out = (u_minus_t >= {1'b0, q}) ? (u_minus_t - {1'b0, q}) : u_minus_t;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            t         <= {DATA_WIDTH{1'b0}};
            t2        <= {DATA_WIDTH{1'b0}};
            shift_reg <= {DATA_WIDTH{1'b0}};
            iter_cnt  <= 4'd0;
            U_out     <= {DATA_WIDTH{1'b0}};
            V_out     <= {DATA_WIDTH{1'b0}};
            done      <= 1'b0;
        end else begin
            state <= next_state;

            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        shift_reg <= twiddle;
                        t2        <= (mode == 1'b0) ? V_in : sub_div2;
                        t         <= {DATA_WIDTH{1'b0}};
                        iter_cnt  <= 4'd0;
                    end
                end

                OP1_MULT: begin
                    if (shift_reg[0]) begin
                        t <= (temp_add >= {1'b0, q}) ? (temp_add - {1'b0, q}) : temp_add;
                    end
                    shift_reg <= shift_reg >> 1;
                    t2        <= (shifted_t2 >= {1'b0, q}) ? (shifted_t2 - {1'b0, q}) : shifted_t2;
                    iter_cnt  <= iter_cnt + 4'd1;
                end

                OP2_ADD: begin
                    U_out <= (mode == 1'b0) ? ct_u_out : add_div2;
                end

                OP3_SUB: begin
                    V_out <= (mode == 1'b0) ? ct_v_out : t; 
                end

                FINISH: begin
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
            IDLE:     if (start) next_state = OP1_MULT;
            OP1_MULT: if (iter_cnt == 4'd11) next_state = OP2_ADD;
            OP2_ADD:  next_state = OP3_SUB;
            OP3_SUB:  next_state = FINISH;
            FINISH:   next_state = IDLE;
            default:  next_state = IDLE;
        endcase
    end

endmodule