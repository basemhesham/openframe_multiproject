// hw_scheduler_top - HARTS scheduler wrapper
// TODO: rename module to harts
module hw_scheduler_top #(
    // clk_freq / (baud_rate * 16). ~115200 at 40 MHz OpenLane clock: 40e6/(115200*16) ≈ 22.
    parameter UART_DIVISOR = 16'd22
)(
    input wire clk,
    input wire rst_n,
    input wire uart_rx,
    output wire uart_tx,
    input wire [7:0] ext_irq,
    output wire irq_n,
    input wire scan_en,
    input wire scan_in,
    output wire scan_out
);
    wire [31:0] apb_paddr;
    wire apb_psel;
    wire apb_penable;
    wire apb_pwrite;
    wire [31:0] apb_pwdata;
    wire [31:0] apb_prdata;
    wire apb_pready;
    wire apb_pslverr;
    wire bridge_locked;

    wire cmd_valid;
    wire [31:0] cmd_word;
    wire cmd_word2_valid;
    wire [31:0] cmd_word2;
    wire [31:0] rsp_word;

    wire timer_enable;
    wire [15:0] tick_divider;
    wire tick_pulse;
    // Split tick_pulse_r into two physically distinct registers: control_unit fans
    // tick into a very wide comb cone (task_table rd_id mux); sleep_queue only needs
    // the tick line. Duplicating the flop cuts Q-pin load and fixes SS setup slack.
    reg tick_pulse_r;
    (* keep = 1 *)
    reg tick_pulse_r_ctrl;
    wire [15:0] tick_counter;

    always @(posedge clk) begin
        if (!rst_n)
            tick_pulse_r <= 1'b0;
        else
            tick_pulse_r <= tick_pulse;
    end

    always @(posedge clk) begin
        if (!rst_n)
            tick_pulse_r_ctrl <= 1'b0;
        else
            tick_pulse_r_ctrl <= tick_pulse;
    end

    wire pq_enqueue;
    wire pq_dequeue;
    wire pq_flush;
    wire [3:0] pq_enq_id;
    wire [15:0] pq_enq_key;
    wire [3:0] pq_head_id;
    wire [15:0] pq_head_key;
    wire pq_head_valid;
    wire [4:0] pq_depth;

    reg pq_enqueue_r;
    reg [3:0] pq_enq_id_r;
    reg [15:0] pq_enq_key_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            pq_enqueue_r <= 1'b0;
            pq_enq_id_r <= 4'd0;
            pq_enq_key_r <= 16'd0;
        end else begin
            pq_enqueue_r <= pq_enqueue;
            pq_enq_id_r <= pq_enq_id;
            pq_enq_key_r <= pq_enq_key;
        end
    end

    wire sq_enqueue;
    wire [3:0] sq_enq_id;
    wire [31:0] sq_enq_counter;
    wire sq_flush;
    wire sq_wake_valid;
    wire [3:0] sq_wake_id;
    wire [4:0] sq_depth;

    wire irq_pending;
    wire fast_irq;
    wire [2:0] irq_index;
    wire [7:0] irq_reason;
    wire [3:0] current_task;
    wire [7:0] fast_mask_r;

    uart_apb_master #(
        .DEFAULT_DIVISOR(UART_DIVISOR)
    ) u_uart_apb (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .PADDR(apb_paddr),
        .PSEL(apb_psel),
        .PENABLE(apb_penable),
        .PWRITE(apb_pwrite),
        .PWDATA(apb_pwdata),
        .PRDATA(apb_prdata),
        .PREADY(apb_pready),
        .PSLVERR(apb_pslverr),
        .locked(bridge_locked)
    );

    harts_apb_slave u_apb_slave (
        .clk(clk),
        .rst_n(rst_n),
        .PADDR(apb_paddr),
        .PSEL(apb_psel),
        .PENABLE(apb_penable),
        .PWRITE(apb_pwrite),
        .PWDATA(apb_pwdata),
        .PRDATA(apb_prdata),
        .PREADY(apb_pready),
        .PSLVERR(apb_pslverr),
        .cmd_valid(cmd_valid),
        .cmd_word(cmd_word),
        .cmd_word2_valid(cmd_word2_valid),
        .cmd_word2(cmd_word2),
        .rsp_word(rsp_word),
        .irq_n(irq_n),
        .irq_reason(irq_reason)
    );

    timer u_timer (
        .clk(clk),
        .rst_n(rst_n),
        .enable(timer_enable),
        .tick_divider(tick_divider),
        .tick_pulse(tick_pulse),
        .tick_counter(tick_counter)
    );

    priority_queue #(.DEPTH(16)) u_pq (
        .clk(clk),
        .rst_n(rst_n),
        .enqueue(pq_enqueue_r),
        .dequeue(pq_dequeue),
        .flush(pq_flush),
        .enq_id(pq_enq_id_r),
        .enq_key(pq_enq_key_r),
        .head_id(pq_head_id),
        .head_key(pq_head_key),
        .head_valid(pq_head_valid),
        .depth(pq_depth)
    );

    sleep_queue u_sq (
        .clk(clk),
        .rst_n(rst_n),
        .flush(sq_flush),
        .enqueue(sq_enqueue),
        .tick(tick_pulse_r),
        .enq_id(sq_enq_id),
        .enq_count(sq_enq_counter),
        .wake_valid(sq_wake_valid),
        .wake_id(sq_wake_id),
        .depth(sq_depth)
    );

    interrupt_ctrl u_irq_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        .ext_irq(ext_irq),
        .fast_mask(fast_mask_r),
        .irq_pending(irq_pending),
        .fast_irq(fast_irq),
        .irq_index(irq_index)
    );

    control_unit u_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        .cmd_valid(cmd_valid),
        .cmd_word(cmd_word),
        .cmd_word2_valid(cmd_word2_valid),
        .cmd_word2(cmd_word2),
        .rsp_word(rsp_word),
        .need_word2(),
        .tick_pulse(tick_pulse_r_ctrl),
        .irq_pending(irq_pending),
        .fast_irq(fast_irq),
        .pq_head_id(pq_head_id),
        .pq_head_key(pq_head_key),
        .pq_head_valid(pq_head_valid),
        .pq_depth(pq_depth),
        .pq_enqueue(pq_enqueue),
        .pq_dequeue(pq_dequeue),
        .pq_flush(pq_flush),
        .pq_enq_id(pq_enq_id),
        .pq_enq_key(pq_enq_key),
        .sq_wake_valid(sq_wake_valid),
        .sq_wake_id(sq_wake_id),
        .sq_depth(sq_depth),
        .sq_enqueue(sq_enqueue),
        .sq_enq_id(sq_enq_id),
        .sq_enq_counter(sq_enq_counter),
        .sq_flush(sq_flush),
        .timer_enable(timer_enable),
        .tick_divider(tick_divider),
        .irq_n(irq_n),
        .irq_reason(irq_reason),
        .current_task(current_task),
        .fast_mask(fast_mask_r)
    );

    wire [255:0] scan_parallel = {
        198'd0,
        irq_reason,
        current_task,
        pq_head_id,
        pq_head_key,
        tick_counter,
        pq_depth,
        sq_depth
    };

    scan_chain #(.WIDTH(256)) u_scan (
        .clk(clk),
        .rst_n(rst_n),
        .scan_en(scan_en),
        .scan_in(scan_in),
        .parallel_in(scan_parallel),
        .scan_out(scan_out)
    );
endmodule
