// TraceGuard-X ASIC — AUC Silicon Sprint
// Module : sram_ctrl
// Process: SKY130 Open PDK
// Authors: Omar Ahmed Fouad, Ahmed Tawfiq, Omar Ahmed Abdelaty
//
// RTL source — see docs/report/ for full module specification.

module sram_ctrl #(
    parameter SRAM_MAX_STATES   = 16, 
    parameter SRAM_MAX_PATTERNS = 1,  
    parameter SRAM_MAX_PAT_LEN  = 15  
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        build_trigger,

    input  wire [4:0]  window_size,


    output reg  [8:0]  sram_addr,
    output reg  [7:0]  sram_wdata,
    output reg         sram_wr_en,
    output reg         sram_rd_en,
    input  wire [7:0]  sram_rdata,

 
    output reg  [3:0]  tbl_wr_state, 
    output reg  [3:0]  tbl_wr_token, 
    output reg  [7:0]  tbl_wr_next,
    output reg         tbl_wr_match,
    output reg  [2:0]  tbl_wr_pat_id,
    output reg         tbl_wr_en,

    output reg         table_ready,
    output reg         building,
    output reg  [7:0]  max_possible,

    input  wire        cmd_sram_req,
    output wire        cmd_sram_grant,
    output reg         overflow_flag,


    input  wire [7:0]  dff_rdata,
    output reg  [7:0]  dff_addr,     
    output reg  [7:0]  dff_wdata,
    output reg         dff_we,
    output reg         dff_en
);

    wire _unused = &{1'b0, cmd_sram_req};
    assign cmd_sram_grant = !building;

    // FSM States
    localparam [19:0] SRAM_S_IDLE       = 20'h00001,
                      SRAM_S_CLEAR_GOTO = 20'h00002,
                      SRAM_S_LOAD_DIR   = 20'h00004,
                      SRAM_S_FETCH_TOK  = 20'h00008,
                      SRAM_S_BUILD_GOTO = 20'h00010,
                      SRAM_S_BG_WAIT    = 20'h00020,
                      SRAM_S_BG_PROC    = 20'h00040,
                      SRAM_S_FI_REQ     = 20'h00080,
                      SRAM_S_FI_WAIT    = 20'h00100,
                      SRAM_S_FI_PROC    = 20'h00200,
                      SRAM_S_BF_PULL    = 20'h00400,
                      SRAM_S_BF_REQ1    = 20'h00800,
                      SRAM_S_BF_WAIT1   = 20'h01000,
                      SRAM_S_BF_PROC1   = 20'h02000,
                      SRAM_S_BF_WAIT2   = 20'h04000,
                      SRAM_S_BF_PROC2   = 20'h08000,
                      SRAM_S_WT_REQ     = 20'h10000,
                      SRAM_S_WT_WAIT    = 20'h20000,
                      SRAM_S_WT_PROC    = 20'h40000,
                      SRAM_S_DONE       = 20'h80000;

    reg [19:0] state;
    reg        rd_wait;
    reg        rd_wait2;

    reg        internal_pat_valid;
    reg [5:0]  internal_pat_len;
    reg [3:0]  current_token_id; 

    reg        match_fn  [0:SRAM_MAX_STATES-1];
    reg [2:0]  pat_id_fn [0:SRAM_MAX_STATES-1];
    reg [3:0]  fail      [0:SRAM_MAX_STATES-1]; 
    reg [4:0]  state_count;                     

    reg [3:0]  bfs_q  [0:SRAM_MAX_STATES-1];    
    reg [4:0]  q_head; 
    reg [4:0]  q_tail; 

    reg [4:0]  c_idx; 
    reg [4:0]  cur_s; 
    reg [7:0]  max_poss_acc;
    reg [4:0]  v;     

    integer j;

    wire [7:0] diff_wp = {3'b0, window_size} - {2'b0, internal_pat_len};
    wire dff_match_fn  = match_fn[dff_rdata[3:0]];

    wire [8:0] next_score_val = {1'b0, max_poss_acc} + {1'b0, diff_wp} + 9'd1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {sram_addr, c_idx} <= 14'd0;
            {sram_wdata, max_poss_acc, dff_wdata} <= 24'd0;
            {sram_wr_en, sram_rd_en, tbl_wr_en, table_ready, dff_we, dff_en, building, rd_wait, rd_wait2, overflow_flag} <= 10'd0;
            {state_count, q_head, q_tail} <= 15'd0;
            {cur_s, v} <= 10'd0;
            dff_addr <= 8'd0;
            max_possible <= 8'd0;
            {tbl_wr_state, tbl_wr_token, tbl_wr_next, tbl_wr_match, tbl_wr_pat_id} <= 20'd0;
            state <= SRAM_S_IDLE;
            internal_pat_valid <= 1'b0;
            internal_pat_len   <= 6'd0;
            current_token_id   <= 4'd0;

            for(j=0; j<SRAM_MAX_STATES; j=j+1) begin match_fn[j]<=0; pat_id_fn[j]<=0; fail[j]<=0; bfs_q[j]<=0; end
        end else begin
            {sram_wr_en, sram_rd_en, tbl_wr_en, table_ready, dff_we, dff_en} <= 6'd0;

            case (state)
                SRAM_S_IDLE: begin
                    {rd_wait, rd_wait2} <= 2'b00;
                    if (build_trigger) begin
                        building     <= 1'b1;
                        max_poss_acc <= 8'd0;
                        state        <= SRAM_S_CLEAR_GOTO;
                        cur_s        <= 5'd0; 
                        c_idx        <= 5'd0;
                    end
                end

                SRAM_S_CLEAR_GOTO: begin
                    dff_addr  <= {cur_s[3:0], c_idx[3:0]}; 
                    dff_wdata <= 8'd0;
                    dff_we    <= 1'b1;
                    dff_en    <= 1'b1;
                    if (c_idx == 0) begin
                        match_fn[cur_s]  <= 1'b0;
                        pat_id_fn[cur_s] <= 3'd0;
                        overflow_flag    <= 1'b0;
                    end
                    
                    if (c_idx == 15) begin
                        c_idx <= 5'd0;
                        if (cur_s == SRAM_MAX_STATES - 1) begin
                            state <= SRAM_S_LOAD_DIR;
                            cur_s <= 5'd0; 
                        end else begin
                            cur_s <= cur_s + 1'b1;
                        end
                    end else begin
                        c_idx <= c_idx + 1'b1;
                    end
                end

                SRAM_S_LOAD_DIR: begin
                    if (!rd_wait && !rd_wait2) begin
                        sram_addr  <= {4'b0, c_idx[4:0]}; 
                        sram_rd_en <= 1'b1;
                        rd_wait    <= 1'b1;
                    end else if (rd_wait && !rd_wait2) begin
                        rd_wait    <= 1'b0;
                        rd_wait2   <= 1'b1;
                    end else if (rd_wait2) begin
                        if (c_idx == 0) internal_pat_valid <= (sram_rdata == 8'hFF);
                        if (c_idx == 1) internal_pat_len   <= sram_rdata[5:0];
                        rd_wait2 <= 1'b0;
                        if (c_idx == 1) begin
                            state <= SRAM_S_BUILD_GOTO;
                            c_idx <= 5'd0;
                            state_count <= 5'd1;
                        end else begin
                            c_idx <= c_idx + 1'b1;
                        end
                    end
                end

                SRAM_S_BUILD_GOTO: begin
                    if (!internal_pat_valid || ({1'b0, c_idx} >= internal_pat_len)) begin
                        state   <= SRAM_S_FI_REQ;
                        c_idx   <= 5'd0;
                        q_head  <= 5'd0;
                        q_tail  <= 5'd0;
                        fail[0] <= 4'd0;
                        if (internal_pat_valid && ({2'b00, window_size} >= {1'b0, internal_pat_len})) begin
                             max_poss_acc <= (next_score_val > 9'd255) ? 8'd255 : next_score_val[7:0];
                        end
                    end else begin

                        current_token_id <= c_idx[3:0] + 4'd1; 
                        state <= SRAM_S_BG_WAIT;
                    end
                end

                SRAM_S_BG_WAIT: begin
                    dff_addr <= {cur_s[3:0], current_token_id};
                    dff_we   <= 1'b0;
                    dff_en   <= 1'b1;
                    state    <= SRAM_S_BG_PROC;
                end

                SRAM_S_BG_PROC: begin
                    if (dff_rdata == 8'd0) begin
                        if (state_count < SRAM_MAX_STATES) begin
                            dff_addr  <= {cur_s[3:0], current_token_id};
                            dff_wdata <= {4'b0, state_count[3:0]};
                            dff_we    <= 1'b1;
                            dff_en    <= 1'b1;
                            cur_s     <= state_count;
                            state_count <= state_count + 1'b1;
                        end else begin
                            overflow_flag <= 1'b1;
                        end
                    end else begin
                        cur_s <= dff_rdata[4:0];
                    end
                    
                    if ({1'b0, c_idx} == (internal_pat_len - 6'd1) && !overflow_flag) begin
                        match_fn[cur_s[3:0]]  <= 1'b1;
                        pat_id_fn[cur_s[3:0]] <= 3'd0;
                    end
                    c_idx <= c_idx + 1'b1;
                    state <= SRAM_S_BUILD_GOTO;
                end

                SRAM_S_FI_REQ: begin
                    if (c_idx < 16) begin 
                        dff_addr <= {4'd0, c_idx[3:0]};
                        dff_we   <= 1'b0;
                        dff_en   <= 1'b1;
                        state    <= SRAM_S_FI_WAIT;
                    end else begin
                        state <= SRAM_S_BF_PULL;
                        c_idx <= 5'd0;
                    end
                end

                SRAM_S_FI_WAIT: state <= SRAM_S_FI_PROC;

                SRAM_S_FI_PROC: begin
                    if (dff_rdata != 8'd0) begin
                        bfs_q[q_tail[3:0]] <= dff_rdata[3:0];
                        q_tail <= q_tail + 1'b1;
                        fail[dff_rdata[3:0]] <= 4'd0;
                    end
                    c_idx <= c_idx + 1'b1;
                    state <= SRAM_S_FI_REQ;
                end

                SRAM_S_BF_PULL: begin
                    if (q_head == q_tail) begin
                        state <= SRAM_S_WT_REQ; cur_s <= 5'd0; c_idx <= 5'd0; 
                    end else begin
                        cur_s  <= {1'b0, bfs_q[q_head[3:0]]};
                        q_head <= q_head + 1'b1;
                        c_idx  <= 5'd0;
                        state  <= SRAM_S_BF_REQ1;
                    end
                end

                SRAM_S_BF_REQ1: begin
                    dff_addr <= {cur_s[3:0], c_idx[3:0]};
                    dff_we   <= 1'b0;
                    dff_en   <= 1'b1;
                    state    <= SRAM_S_BF_WAIT1;
                end

                SRAM_S_BF_WAIT1: state <= SRAM_S_BF_PROC1;

                SRAM_S_BF_PROC1: begin
                    v <= {1'b0, dff_rdata[3:0]}; 
                    dff_addr <= {fail[cur_s][3:0], c_idx[3:0]};
                    dff_we   <= 1'b0;
                    dff_en   <= 1'b1;
                    state    <= SRAM_S_BF_WAIT2;
                end

                SRAM_S_BF_WAIT2: state <= SRAM_S_BF_PROC2;

                SRAM_S_BF_PROC2: begin
                    if (v > 0) begin
                        fail[v] <= dff_rdata[3:0];
                        if (dff_match_fn) begin
                            match_fn[v]  <= 1'b1;
                            pat_id_fn[v] <= pat_id_fn[dff_rdata[3:0]];
                        end
                        bfs_q[q_tail[3:0]] <= v[3:0];
                        q_tail <= q_tail + 1'b1;
                    end else begin
                        dff_addr  <= {cur_s[3:0], c_idx[3:0]};
                        dff_wdata <= dff_rdata;
                        dff_we    <= 1'b1;
                        dff_en    <= 1'b1;
                    end
                    if (c_idx == 15) state <= SRAM_S_BF_PULL;
                    else begin c_idx <= c_idx + 1'b1; state <= SRAM_S_BF_REQ1; end
                end

                SRAM_S_WT_REQ: begin
                    dff_addr <= {cur_s[3:0], c_idx[3:0]};
                    dff_we   <= 1'b0;
                    dff_en   <= 1'b1;
                    state    <= SRAM_S_WT_WAIT;
                end

                SRAM_S_WT_WAIT: state <= SRAM_S_WT_PROC;

                SRAM_S_WT_PROC: begin
                    tbl_wr_en     <= 1'b1;
                    tbl_wr_state  <= cur_s[3:0];
                    tbl_wr_token  <= c_idx[3:0];
                    tbl_wr_next   <= dff_rdata;
                    tbl_wr_match  <= match_fn[ dff_rdata[3:0] ];
                    tbl_wr_pat_id <= 3'd0;

                    if (c_idx == 15) begin
                        c_idx <= 5'd0;
                        if (cur_s == SRAM_MAX_STATES - 1) state <= SRAM_S_DONE;
                        else begin cur_s <= cur_s + 1'b1; state <= SRAM_S_WT_REQ; end
                    end else begin
                        c_idx <= c_idx + 1'b1;
                        state <= SRAM_S_WT_REQ;
                    end
                end

                SRAM_S_DONE: begin
                    max_possible  <= max_poss_acc;
                    table_ready   <= 1'b1;
                    building      <= 1'b0;
                    overflow_flag <= 1'b0; 
                    state         <= SRAM_S_IDLE;
                end

                default: state <= SRAM_S_IDLE;
            endcase
        end
    end

endmodule
