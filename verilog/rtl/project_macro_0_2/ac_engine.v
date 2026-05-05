// TraceGuard-X ASIC — AUC Silicon Sprint
// Module : ac_engine
// Process: SKY130 Open PDK
// Authors: Omar Ahmed Fouad, Ahmed Tawfiq, Omar Ahmed Abdelaty
//
// RTL source — see docs/report/ for full module specification.

module ac_engine #(
    parameter AC_MAX_STATES  = 16, 
    parameter AC_MAX_WIN     = 32,
    parameter AC_TOKEN_WIDTH = 4   
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire        ac_reset_n,


    input  wire [AC_TOKEN_WIDTH-1:0] token_in,
    input  wire [4:0]  window_size,
    input  wire        token_valid,

    
    input  wire [3:0]  tbl_wr_state, 
    input  wire [3:0]  tbl_wr_token, 
    input  wire [7:0]  tbl_wr_next,  
    input  wire        tbl_wr_match,
    input  wire [2:0]  tbl_wr_pat_id,
    input  wire        tbl_wr_en,

    
    output wire [7:0]  dff_addr,     
    output wire [7:0]  dff_din,
    output wire        dff_we,
    output wire        dff_en,
    input  wire [7:0]  dff_dout,

    
    output reg  [7:0]  match_count,
    output reg  [2:0]  last_pattern_id,
    output reg  [7:0]  confidence,
    output reg         done,
    output wire        processing,
    output reg         hold_alert
);

    
    reg       is_match   [0:AC_MAX_STATES-1];
    reg [2:0] pattern_id [0:AC_MAX_STATES-1];
    integer i;

    always @(posedge clk) begin
        if (!ac_reset_n) begin
            for (i = 0; i < AC_MAX_STATES; i = i + 1) begin
                is_match[i]   <= 1'b0;
                pattern_id[i] <= 3'd0;
            end
        end else if (tbl_wr_en) begin
            
            is_match[tbl_wr_next[3:0]]   <= tbl_wr_match;
            pattern_id[tbl_wr_next[3:0]] <= tbl_wr_pat_id;
        end
    end

    
    reg [7:0] read_addr; 
    reg       read_en;
    
    
    assign dff_addr = tbl_wr_en ? {tbl_wr_state, tbl_wr_token} : read_addr;
    
    
    wire [7:0] dff_din_buf = tbl_wr_next;
    assign dff_din  = dff_din_buf;
    
    wire dff_we_buf = tbl_wr_en;
    assign dff_we   = dff_we_buf;
    assign dff_en   = tbl_wr_en | read_en;

    
    localparam [5:0] AC_S_IDLE      = 6'b000001;
    localparam [5:0] AC_S_WAIT_ROOT = 6'b000010;
    localparam [5:0] AC_S_EVAL_ROOT = 6'b000100;
    localparam [5:0] AC_S_HOLD      = 6'b001000;
    localparam [5:0] AC_S_WAIT_NODE = 6'b010000;
    localparam [5:0] AC_S_EVAL_NODE = 6'b100000;

    reg [5:0] fsm_state;
    reg [5:0] grace_ctr;
    reg       chain_broken;
    reg [3:0] curr_node; 

    wire [5:0] eff_size = (window_size == 5'd0) ? 6'd32 : {1'b0, window_size};
    assign processing = (fsm_state != AC_S_IDLE);
    
    
    wire curr_is_match = is_match[dff_dout[3:0]];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fsm_state <= AC_S_IDLE;
            {match_count, confidence} <= 16'd0;
            {last_pattern_id, done, hold_alert, read_en, chain_broken} <= 7'd0;
            read_addr <= 8'd0;
            grace_ctr <= 6'd0;
            curr_node <= 4'd0;
        end else if (!ac_reset_n) begin
            fsm_state <= AC_S_IDLE;
            {match_count, done, hold_alert, read_en} <= 11'd0;
        end else begin
            case (fsm_state)
                AC_S_IDLE: begin
                    done <= 1'b0;
                    read_en <= 1'b0;
                    if (en && token_valid) begin
                        
                        read_addr <= {4'd0, token_in};
                        read_en   <= 1'b1;            
                        fsm_state <= AC_S_WAIT_ROOT;      
                    end
                end

                AC_S_WAIT_ROOT: begin
                    read_en   <= 1'b0;
                    fsm_state <= AC_S_EVAL_ROOT; 
                end

                AC_S_EVAL_ROOT: begin
                    if (dff_dout > 0) begin
                        match_count  <= 8'd1;
                        curr_node    <= dff_dout[3:0]; 
                        grace_ctr    <= 6'd1;
                        chain_broken <= 1'b0;
                        if (curr_is_match) last_pattern_id <= pattern_id[dff_dout[3:0]];
                        
                        if (eff_size == 6'd1) begin
                            hold_alert <= 1'b0; done <= 1'b1; fsm_state <= AC_S_IDLE;
                        end else begin
                            hold_alert <= 1'b1; fsm_state <= AC_S_HOLD;
                        end
                    end else begin
                        match_count <= 8'd0;
                        hold_alert  <= 1'b0;
                        done        <= 1'b1;
                        fsm_state   <= AC_S_IDLE;
                    end
                end

                AC_S_HOLD: begin
                    done <= 1'b0;
                    if (en && token_valid) begin
                        grace_ctr <= grace_ctr + 1'b1;
                        if (!chain_broken) begin
                            
                            read_addr <= {curr_node, token_in};
                            read_en   <= 1'b1;
                            fsm_state <= AC_S_WAIT_NODE; 
                        end else begin
                            fsm_state <= AC_S_EVAL_NODE; 
                        end
                    end
                end

                AC_S_WAIT_NODE: begin
                    read_en   <= 1'b0;
                    fsm_state <= AC_S_EVAL_NODE; 
                end

                AC_S_EVAL_NODE: begin
                    if (!chain_broken) begin
                        if (dff_dout > 0) begin
                            match_count <= match_count + 1'b1;
                            curr_node   <= dff_dout[3:0]; 
                            if (curr_is_match) last_pattern_id <= pattern_id[dff_dout[3:0]];
                        end else begin
                            chain_broken <= 1'b1; 
                        end
                    end

                    if (grace_ctr >= eff_size) begin
                        hold_alert <= 1'b0; 
                        done       <= 1'b1;
                        fsm_state  <= AC_S_IDLE;
                    end else begin
                        fsm_state  <= AC_S_HOLD;
                    end
                end
                
                default: fsm_state <= AC_S_IDLE;
            endcase
        end
    end
endmodule
