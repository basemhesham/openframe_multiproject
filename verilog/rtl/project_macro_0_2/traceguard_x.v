// TraceGuard-X ASIC — AUC Silicon Sprint
// Module : traceguard_x
// Process: SKY130 Open PDK
// Authors: Omar Ahmed Fouad, Ahmed Tawfiq, Omar Ahmed Abdelaty
//
// RTL source — see docs/report/ for full module specification.

module traceguard_x #(
    parameter TOP_CLK_FREQ        = 25_000_000,
    parameter TOP_BAUD_RATE       = 115_200,
    parameter TOP_WATCHDOG_CYCLES = 25_000_000
) (
    input  wire clk,
    input  wire rst_n,
    input  wire uart_rx,
    output wire uart_tx,
    output wire gpio_alert,
    output wire gpio_match,
    output wire gpio_busy,
    output wire gpio_ready,
    output wire       gpio_overflow,
    output wire       gpio_wd_alert,
    output wire [1:0] gpio_mode,
    output wire [7:0] gpio_score
);

    wire    tbl_rdy, bld_active;

 
    wire [7:0] dff_addr_ac, dff_addr_ctrl, dff_addr_mux; 
    wire [7:0]  dff_din_ac,  dff_din_ctrl,  dff_din_mux;
    wire        dff_we_ac,   dff_we_ctrl,   dff_we_mux;
    wire        dff_en_ac,   dff_en_ctrl,   dff_en_mux;
    wire [7:0]  dff_dout;

    wire use_ctrl = bld_active;

    assign dff_addr_mux = use_ctrl ? dff_addr_ctrl : dff_addr_ac;
    assign dff_din_mux  = use_ctrl ? dff_din_ctrl  : dff_din_ac;
    assign dff_we_mux   = use_ctrl ? dff_we_ctrl   : dff_we_ac;
    assign dff_en_mux   = use_ctrl ? dff_en_ctrl   : dff_en_ac;


    RAM256_Banked u_shared_dffram (
        .CLK(clk),
        .WE0(dff_we_mux),
        .EN0(dff_en_mux),
        .A0(dff_addr_mux),
        .Di0(dff_din_mux),
        .Do0(dff_dout)
    );

    wire [7:0] rx_data;
    wire       rx_valid, rx_ready, uart_tx_ready;

    wire [1:0] cmd_mode;
    wire       cmd_mode_vld, lock_cmd, lock_granted;
    wire[15:0] pin_data;
    wire [7:0] thresh_reg;
    wire       thresh_wr, win_size_wr;
    wire [4:0] win_size;
    wire [7:0] cmd_tx_data, stream_token;
    wire       cmd_tx_valid, stream_valid, send_result_req;

    wire [8:0] sram_addr, cmd_sram_addr, ctrl_sram_addr;
    wire [7:0] sram_wdata, cmd_sram_wdata, ctrl_sram_wdata, sram_rdata;
    wire       sram_wr_en, cmd_sram_wr, ctrl_sram_wr;
    wire       sram_rd_en, cmd_sram_rd, ctrl_sram_rd;
    wire       cmd_sram_grant, sram_ctrl_grant_inv;

    wire [1:0] mode;
    wire       en_win, en_ac, en_score, en_out;
    wire       ac_rst_n, build_tbl, wd_alert; 

 
    wire [3:0] tw_state; 
    wire [3:0] tw_tok;  
    wire [7:0] tw_nxt;
    wire       tw_match, tw_en;
    wire [2:0] tw_pat_id;
    
    wire [7:0] win_out;
    wire       win_rdy;

    wire [7:0] match_cnt, conf;
    wire [2:0] last_pat;
    wire       ac_done, ac_proc, hold_alert_w; 

    wire [7:0] score, out_tx_data;
    wire       alert_flg, match_flg, out_tx_valid, overflow_w;


    wire [3:0] mapped_tok_id;

    assign sram_ctrl_grant_inv = !cmd_sram_grant;
    assign sram_addr  = sram_ctrl_grant_inv ? ctrl_sram_addr  : cmd_sram_addr;
    assign sram_wdata = sram_ctrl_grant_inv ? ctrl_sram_wdata : cmd_sram_wdata;
    assign sram_wr_en = sram_ctrl_grant_inv ? ctrl_sram_wr    : cmd_sram_wr;
    assign sram_rd_en = sram_ctrl_grant_inv ? ctrl_sram_rd    : cmd_sram_rd;

    wire [7:0] mux_tx_data  = out_tx_valid ? out_tx_data : cmd_tx_data;
    wire       mux_tx_valid = out_tx_valid | cmd_tx_valid;
    wire       cmd_sram_req_w = cmd_sram_wr | cmd_sram_rd;

    assign gpio_overflow = overflow_w;
    assign gpio_wd_alert = wd_alert;
    assign gpio_mode     = mode;
    assign gpio_score    = score;

    wire unused_rx_ovf, unused_frame_err, unused_tx_busy;
    wire unused_win_size_wr, unused_chip_locked, unused_pipe_en, unused_sram_wr_allow;
    wire unused_processing;
    wire [7:0] unused_trans_log;

    pattern_sram #(
        .MAX_STATES(16)
    ) u_pattern_sram (
        .clk(clk), .rst_n(rst_n), .addr(sram_addr), .data_in(sram_wdata),
        .wr_en(sram_wr_en), .rd_en(sram_rd_en), .data_out(sram_rdata), .busy()
    );

    uart_trx #( .TRX_CLK_FREQ(TOP_CLK_FREQ), .TRX_BAUD_RATE(TOP_BAUD_RATE) ) u_uart_trx (
        .clk(clk), .rst_n(rst_n), .uart_rx(uart_rx), .uart_tx(uart_tx),
        .rx_data(rx_data), .rx_valid(rx_valid), .rx_ready(rx_ready),
        .tx_data(mux_tx_data), .tx_valid(mux_tx_valid), .tx_ready(uart_tx_ready),
        .rx_overflow(unused_rx_ovf), .frame_error(unused_frame_err), .tx_busy(unused_tx_busy)
    );

    cmd_decoder #(
        .MAX_STATES(16)
    ) u_cmd_decoder (
        .clk(clk), .rst_n(rst_n), .rx_data(rx_data), .rx_valid(rx_valid), .rx_ready(rx_ready),
        .mode_cmd(cmd_mode), .mode_cmd_valid(cmd_mode_vld),
        .sram_addr(cmd_sram_addr), .sram_wdata(cmd_sram_wdata),
        .sram_wr_en(cmd_sram_wr), .sram_rd_en(cmd_sram_rd), .sram_rdata(sram_rdata),
        .threshold_reg(thresh_reg), .threshold_wr(thresh_wr),
        .window_size(win_size), .window_size_wr(unused_win_size_wr),
        .tx_data(cmd_tx_data), .tx_valid(cmd_tx_valid), .tx_ready(uart_tx_ready),
        .lock_cmd(lock_cmd), .pin_data(pin_data), .lock_granted(lock_granted),
        .stream_token(stream_token), .stream_valid(stream_valid),
        .send_result_req(send_result_req), .score_in(score), .mode_in(mode),
        .flags_in({gpio_alert, gpio_match, gpio_busy, gpio_ready}),.overflow_wire(overflow_w)
    );

    ctrl_fsm #( .FSM_CLK_FREQ(TOP_CLK_FREQ), .FSM_WATCHDOG_CYCLES(TOP_WATCHDOG_CYCLES) ) u_ctrl_fsm (
        .clk(clk), .rst_n(rst_n), .mode_cmd(cmd_mode), .mode_cmd_valid(cmd_mode_vld),
        .lock_cmd(lock_cmd), .pin_data(pin_data), .table_ready(tbl_rdy),
        .uart_activity(rx_valid),
        .mode(mode), .en_sliding_win(en_win), .en_ac_engine(en_ac),
        .en_score_unit(en_score), .en_output_reg(en_out),
        .sram_wr_allow(unused_sram_wr_allow), .ac_reset_n(ac_rst_n),  
        .build_table(build_tbl), .pipeline_en(unused_pipe_en),   
        .lock_granted(lock_granted), .chip_locked(unused_chip_locked), .watchdog_alert(wd_alert), 
        .mode_out(), .transition_log(unused_trans_log)
    );

    sram_ctrl #(
        .SRAM_MAX_STATES(16),
        .SRAM_MAX_PAT_LEN(15)
    ) u_sram_ctrl (
        .clk(clk), .rst_n(rst_n), .build_trigger(build_tbl), .window_size(win_size),
        .sram_addr(ctrl_sram_addr), .sram_wdata(ctrl_sram_wdata),
        .sram_wr_en(ctrl_sram_wr), .sram_rd_en(ctrl_sram_rd), .sram_rdata(sram_rdata),
        .tbl_wr_state(tw_state), .tbl_wr_token(tw_tok), .tbl_wr_next(tw_nxt),
        .tbl_wr_match(tw_match), .tbl_wr_pat_id(tw_pat_id), .tbl_wr_en(tw_en),
        .table_ready(tbl_rdy), .building(bld_active), .max_possible(), 
        .cmd_sram_req(cmd_sram_req_w), .cmd_sram_grant(cmd_sram_grant),.overflow_flag(overflow_w),
        .dff_addr(dff_addr_ctrl), .dff_wdata(dff_din_ctrl), .dff_we(dff_we_ctrl), .dff_en(dff_en_ctrl), .dff_rdata(dff_dout)
    );

    sliding_window u_sliding_window (
        .clk(clk), .rst_n(rst_n), .en(en_win),
        .token_in(stream_token), .token_valid(stream_valid),
        .window_size(win_size), .flush(build_tbl),
        .window_out(win_out), .window_ready(win_rdy)
    );


    token_decoder #(
        .MAX_STATES(16),
        .TOKEN_WIDTH(8)
    ) u_token_decoder (
        .clk(clk),
        .rst_n(rst_n),
        .learn_en(cmd_sram_wr),
        .learn_addr(cmd_sram_addr),
        .learn_data(cmd_sram_wdata),
        .token_in(win_out),
        .mapped_id(mapped_tok_id)
    );

    ac_engine #(
        .AC_MAX_STATES(16),
        .AC_TOKEN_WIDTH(4)
    ) u_ac_engine (
        .clk(clk), .rst_n(rst_n), .en(en_ac), .ac_reset_n(ac_rst_n),
        .token_in(mapped_tok_id), 
        .window_size(win_size), .token_valid(win_rdy),
        .tbl_wr_state(tw_state), .tbl_wr_token(tw_tok), .tbl_wr_next(tw_nxt),
        .tbl_wr_match(tw_match), .tbl_wr_pat_id(tw_pat_id), .tbl_wr_en(tw_en),
        .match_count(match_cnt), .last_pattern_id(last_pat),
        .confidence(conf), .done(ac_done), .processing(ac_proc), .hold_alert(hold_alert_w),
        .dff_addr(dff_addr_ac), .dff_din(dff_din_ac), .dff_we(dff_we_ac), .dff_en(dff_en_ac), .dff_dout(dff_dout)
    );

    score_unit u_score_unit (
        .clk(clk), .rst_n(rst_n), .en(en_score),
        .match_count(match_cnt), .confidence(conf), .last_pattern_id(last_pat),
        .ac_done(ac_done), .hold_alert(hold_alert_w),
        .threshold(thresh_reg), .threshold_wr(thresh_wr), .window_size(win_size),
        .score(score), .alert_flag(alert_flg), .match_flag(match_flg), .processing(unused_processing)
    );

    output_reg u_output_reg (
        .clk(clk), .rst_n(rst_n), .en(en_out),
        .alert_in(alert_flg), .match_in(match_flg), .ac_processing(ac_proc), .mode(mode),
        .score_in(score), .pattern_id_in(last_pat), .watchdog_alert(wd_alert),
        .send_status_req(1'b0), .send_result_req(send_result_req),
        .match_count_in(match_cnt), .confidence_in(conf),
        .tx_data(out_tx_data), .tx_valid(out_tx_valid), .tx_ready(uart_tx_ready),
        .gpio_alert(gpio_alert), .gpio_match(gpio_match),
        .gpio_busy(gpio_busy), .gpio_ready(gpio_ready)
    );

endmodule
