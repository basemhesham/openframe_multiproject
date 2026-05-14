module control_unit #(
    parameter NUM_TASKS = 16,
    parameter ID_WIDTH = 4,
    parameter KEY_WIDTH = 16
) (
    input wire clk,
    input wire rst_n,
    input wire cmd_valid,
    input wire [31:0] cmd_word,
    input wire cmd_word2_valid,
    input wire [31:0] cmd_word2,
    output reg [31:0] rsp_word,
    output reg need_word2,
    input wire tick_pulse,
    input wire irq_pending,
    input wire fast_irq,
    input wire [ID_WIDTH-1:0] pq_head_id,
    input wire [KEY_WIDTH-1:0] pq_head_key,
    input wire pq_head_valid,
    input wire [4:0] pq_depth,
    output reg pq_enqueue,
    output reg pq_dequeue,
    output reg pq_flush,
    output reg [ID_WIDTH-1:0] pq_enq_id,
    output reg [KEY_WIDTH-1:0] pq_enq_key,
    input wire sq_wake_valid,
    input wire [ID_WIDTH-1:0] sq_wake_id,
    input wire [4:0] sq_depth,
    output reg sq_enqueue,
    output reg [ID_WIDTH-1:0] sq_enq_id,
    output reg [31:0] sq_enq_counter,
    output reg sq_flush,
    output reg timer_enable,
    output reg [15:0] tick_divider,
    output reg irq_n,
    output reg [7:0] irq_reason,
    output reg [ID_WIDTH-1:0] current_task,
    output reg [7:0] fast_mask
);
    localparam OP_NOP = 4'h0;
    localparam OP_CONFIG = 4'h1;
    localparam OP_RUN = 4'h2;
    localparam OP_STOP = 4'h3;
    localparam OP_CREATE = 4'h4;
    localparam OP_DELETE = 4'h5;
    localparam OP_MODIFY = 4'h6;
    localparam OP_SLEEP = 4'h7;
    localparam OP_SSLEEP = 4'h8; // short sleep: 24-bit count packed in cmd[23:0], no second word
    localparam OP_YIELD = 4'h9;
    localparam OP_SUSPEND = 4'ha;
    localparam OP_RESUME = 4'hb;
    localparam OP_ACTIVATE = 4'hc;
    localparam OP_QUERY = 4'hd;
    localparam OP_SCAN = 4'he;
    localparam OP_RESET = 4'hf;

    reg [1:0] sched_mode;
    reg [7:0] flags_reg;
    reg [31:0] tick_count;
    reg pending_word2;
    reg [3:0] pending_opcode;
    reg [3:0] pending_task_id;
    reg [31:0] pending_word1;

    reg tt_wr_en;
    reg [ID_WIDTH-1:0] tt_wr_id;
    reg [3:0] tt_wr_priority;
    reg [15:0] tt_wr_period;
    reg [15:0] tt_wr_deadline;
    reg [15:0] tt_wr_wcet;
    reg tt_wr_type;
    reg tt_wr_preemptable;
    reg [2:0] tt_wr_status;
    reg [15:0] tt_wr_abs_deadline;
    reg [15:0] tt_wr_remaining_wcet;
    reg [ID_WIDTH-1:0] tt_rd_id;
    reg tt_clear_all;
    reg [15:0] pq_eff_abs_deadline;
    reg [15:0] pq_eff_remaining_wcet;
    // Registered copy of current_task for tick-time table reads: shortens tick_pulse
    // -> tt_rd_id -> task_table comb paths (tick_pulse only mux-selects a flop).
    reg [ID_WIDTH-1:0] tt_rd_id_tick;

    wire [3:0] tt_rd_priority;
    wire [15:0] tt_rd_period;
    wire [15:0] tt_rd_deadline;
    wire [15:0] tt_rd_wcet;
    wire tt_rd_type;
    wire tt_rd_preemptable;
    wire [2:0] tt_rd_status;
    wire [15:0] tt_rd_abs_deadline;
    wire [15:0] tt_rd_remaining_wcet;

    wire [3:0] opcode = cmd_word[31:28];
    wire [3:0] task_id = cmd_word[27:24];

    task automatic prep_tt_write;
        input [ID_WIDTH-1:0] id;
        begin
            tt_wr_en <= 1'b1;
            tt_wr_id <= id;
            tt_wr_priority <= tt_rd_priority;
            tt_wr_period <= tt_rd_period;
            tt_wr_deadline <= tt_rd_deadline;
            tt_wr_wcet <= tt_rd_wcet;
            tt_wr_type <= tt_rd_type;
            tt_wr_preemptable <= tt_rd_preemptable;
            tt_wr_status <= tt_rd_status;
            tt_wr_abs_deadline <= tt_rd_abs_deadline;
            tt_wr_remaining_wcet <= tt_rd_remaining_wcet;
        end
    endtask

    task_table #(
        .NUM_TASKS(NUM_TASKS),
        .ID_WIDTH(ID_WIDTH)
    ) u_task_table (
        .clk(clk),
        .rst_n(rst_n),
        .clear_all(tt_clear_all),
        .wr_en(tt_wr_en),
        .wr_id(tt_wr_id),
        .wr_priority(tt_wr_priority),
        .wr_period(tt_wr_period),
        .wr_deadline(tt_wr_deadline),
        .wr_wcet(tt_wr_wcet),
        .wr_type(tt_wr_type),
        .wr_preemptable(tt_wr_preemptable),
        .wr_status(tt_wr_status),
        .wr_abs_deadline(tt_wr_abs_deadline),
        .wr_remaining_wcet(tt_wr_remaining_wcet),
        .rd_en(1'b1),
        .rd_id(tt_rd_id),
        .rd_priority(tt_rd_priority),
        .rd_period(tt_rd_period),
        .rd_deadline(tt_rd_deadline),
        .rd_wcet(tt_rd_wcet),
        .rd_type(tt_rd_type),
        .rd_preemptable(tt_rd_preemptable),
        .rd_status(tt_rd_status),
        .rd_abs_deadline(tt_rd_abs_deadline),
        .rd_remaining_wcet(tt_rd_remaining_wcet)
    );

    always @(*) begin
        tt_rd_id = task_id;
        if (tick_pulse) tt_rd_id = tt_rd_id_tick;
        if (pending_word2) tt_rd_id = pending_task_id;
        if (sq_wake_valid) tt_rd_id = sq_wake_id;
        // OP_ACTIVATE reads pq_head so prep_tt_write copies the correct descriptor
        if (cmd_valid && opcode == OP_ACTIVATE) tt_rd_id = pq_head_id;

        // LLF needs an abs_deadline that may not yet be committed to the task table:
        // at RESUME the NBA hasn't landed, so compute it fresh; otherwise use stored value.
        if (cmd_valid && opcode == OP_RESUME)
            pq_eff_abs_deadline = tick_count[15:0] + tt_rd_deadline;
        else
            pq_eff_abs_deadline = tt_rd_abs_deadline;

        // At sq_wake the task just woke from sleep; remaining_wcet should be the full
        // wcet for the new period, not the (possibly depleted) stored value.
        if (sq_wake_valid)
            pq_eff_remaining_wcet = tt_rd_wcet;
        else
            pq_eff_remaining_wcet = tt_rd_remaining_wcet;

        case (sched_mode)
            2'b00: pq_enq_key = {12'd0, tt_rd_priority};
            2'b01: pq_enq_key = ~tt_rd_period;
            2'b10: pq_enq_key = ~(tick_count[15:0] + tt_rd_deadline);
            default: pq_enq_key = ~(pq_eff_abs_deadline - pq_eff_remaining_wcet);
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sched_mode <= 2'b00;
            flags_reg <= 8'd0;
            tick_divider <= 16'd100;
            timer_enable <= 1'b0;
            irq_n <= 1'b1;
            irq_reason <= 8'd0;
            rsp_word <= 32'd0;
            need_word2 <= 1'b0;
            pq_enqueue <= 1'b0;
            pq_dequeue <= 1'b0;
            pq_flush <= 1'b1;
            sq_enqueue <= 1'b0;
            sq_flush <= 1'b1;
            current_task <= {ID_WIDTH{1'b1}};
            fast_mask <= 8'hff;
            tick_count <= 0;
            pending_word2 <= 1'b0;
            pending_opcode <= 4'd0;
            pending_task_id <= 4'd0;
            pending_word1 <= 32'd0;
            tt_wr_en <= 1'b0;
            tt_clear_all <= 1'b1;
            tt_wr_id <= 0;
            tt_wr_priority <= 0;
            tt_wr_period <= 0;
            tt_wr_deadline <= 0;
            tt_wr_wcet <= 0;
            tt_wr_type <= 0;
            tt_wr_preemptable <= 0;
            tt_wr_status <= 0;
            tt_wr_abs_deadline <= 0;
            tt_wr_remaining_wcet <= 0;
            tt_rd_id_tick <= {ID_WIDTH{1'b1}};
        end else begin
            tt_rd_id_tick <= current_task;
            tt_wr_en <= 1'b0;
            tt_clear_all <= 1'b0;
            pq_enqueue <= 1'b0;
            pq_dequeue <= 1'b0;
            pq_flush <= 1'b0;
            sq_enqueue <= 1'b0;
            sq_flush <= 1'b0;
            need_word2 <= 1'b0;

            if (tick_pulse) begin
                tick_count <= tick_count + 1;
                // decrement remaining_wcet for the running task (needed for correct LLF key)
                // skip if cmd_valid or sq_wake_valid to avoid task-table write conflicts
                if (!cmd_valid && !sq_wake_valid &&
                    current_task != {ID_WIDTH{1'b1}} && tt_rd_status == 3'b011 &&
                    tt_rd_remaining_wcet != 16'd0) begin
                    prep_tt_write(current_task);
                    tt_wr_remaining_wcet <= tt_rd_remaining_wcet - 16'd1;
                end
            end

            if (pending_word2 && cmd_word2_valid) begin
                pending_word2 <= 1'b0;
                case (pending_opcode)
                    OP_CREATE: begin
                        prep_tt_write(pending_task_id);
                        tt_wr_priority <= pending_word1[23:20];
                        tt_wr_type <= pending_word1[19];
                        tt_wr_preemptable <= pending_word1[18];
                        tt_wr_period <= cmd_word2[31:16];
                        tt_wr_wcet <= cmd_word2[15:0];
                        tt_wr_deadline <= pending_word1[15:0];
                        tt_wr_status <= 3'b001;
                        tt_wr_abs_deadline <= tick_count[15:0] + pending_word1[15:0];
                        tt_wr_remaining_wcet <= cmd_word2[15:0];
                        rsp_word <= 32'h0000_c004;
                    end
                    OP_MODIFY: begin
                        prep_tt_write(pending_task_id);
                        tt_wr_priority <= pending_word1[23:20];
                        tt_wr_type <= pending_word1[19];
                        tt_wr_preemptable <= pending_word1[18];
                        tt_wr_period <= cmd_word2[31:16];
                        tt_wr_wcet <= cmd_word2[15:0];
                        tt_wr_deadline <= pending_word1[15:0];
                        tt_wr_abs_deadline <= tick_count[15:0] + pending_word1[15:0];
                        tt_wr_remaining_wcet <= cmd_word2[15:0];
                        rsp_word <= 32'h0000_c006;
                    end
                    OP_SLEEP: begin
                        sq_enq_id <= pending_task_id;
                        sq_enq_counter <= cmd_word2;
                        sq_enqueue <= 1'b1;
                        prep_tt_write(pending_task_id);
                        tt_wr_status <= 3'b100;
                        rsp_word <= 32'h0000_c007;
                    end
                    default: rsp_word <= 32'hdead_0002;
                endcase
            end

            if (cmd_valid) begin
                irq_n <= 1'b1;
                case (opcode)
                    OP_NOP: rsp_word <= 32'h0000_0000;
                    OP_CONFIG: begin
                        fast_mask <= cmd_word[27:20];
                        sched_mode <= cmd_word[17:16];
                        tick_divider <= {8'd0, cmd_word[15:8]};
                        flags_reg <= cmd_word[7:0];
                        rsp_word <= 32'h0000_c001;
                    end
                    OP_RUN: begin
                        timer_enable <= 1'b1;
                        rsp_word <= 32'h0000_c002;
                    end
                    OP_STOP: begin
                        timer_enable <= 1'b0;
                        rsp_word <= 32'h0000_c003;
                    end
                    OP_CREATE: begin
                        need_word2 <= 1'b1;
                        pending_word2 <= 1'b1;
                        pending_opcode <= OP_CREATE;
                        pending_task_id <= task_id;
                        pending_word1 <= cmd_word;
                    end
                    OP_MODIFY: begin
                        need_word2 <= 1'b1;
                        pending_word2 <= 1'b1;
                        pending_opcode <= OP_MODIFY;
                        pending_task_id <= task_id;
                        pending_word1 <= cmd_word;
                    end
                    OP_DELETE: begin
                        prep_tt_write(task_id);
                        tt_wr_status <= 3'b000;
                        rsp_word <= 32'h0000_c005;
                    end
                    OP_SLEEP: begin
                        need_word2 <= 1'b1;
                        pending_word2 <= 1'b1;
                        pending_opcode <= OP_SLEEP;
                        pending_task_id <= task_id;
                        pending_word1 <= cmd_word;
                    end
                    OP_SSLEEP: begin
                        sq_enq_id <= task_id;
                        sq_enq_counter <= {8'd0, cmd_word[23:0]};
                        sq_enqueue <= 1'b1;
                        prep_tt_write(task_id);
                        tt_wr_status <= 3'b100;
                        rsp_word <= 32'h0000_c008;
                    end
                    OP_YIELD: begin
                        if (tt_rd_period != 16'd0) begin
                            sq_enq_id <= task_id;
                            sq_enq_counter <= tt_rd_period;
                            sq_enqueue <= 1'b1;
                            prep_tt_write(task_id);
                            tt_wr_status <= 3'b100;
                            // pre-compute abs_deadline for the next period so LLF key
                            // is correct when the task wakes from the sleep queue
                            tt_wr_abs_deadline <= tick_count[15:0] + tt_rd_period + tt_rd_deadline;
                            tt_wr_remaining_wcet <= tt_rd_wcet;
                            rsp_word <= 32'h0000_c009;
                        end else begin
                            rsp_word <= 32'hdead_0004; // error: aperiodic task cannot yield
                        end
                    end
                    OP_SUSPEND: begin
                        prep_tt_write(task_id);
                        tt_wr_status <= 3'b001;
                        rsp_word <= 32'h0000_c00a;
                    end
                    OP_RESUME: begin
                        // move task from suspended to ready, enqueue to priority queue
                        prep_tt_write(task_id);
                        tt_wr_status <= 3'b010;
                        tt_wr_abs_deadline <= tick_count[15:0] + tt_rd_deadline;
                        tt_wr_remaining_wcet <= tt_rd_wcet;
                        pq_enq_id <= task_id;
                        pq_enqueue <= 1'b1;
                        rsp_word <= 32'h0000_c00b;
                    end
                    OP_ACTIVATE: begin
                        // dequeue highest-priority ready task and set it running
                        // tt_rd_id mux above redirects to pq_head_id for this opcode
                        if (pq_head_valid) begin
                            current_task <= pq_head_id;
                            pq_dequeue <= 1'b1;
                            prep_tt_write(pq_head_id);
                            tt_wr_status <= 3'b011;
                            rsp_word <= 32'h0000_c00c;
                        end else begin
                            rsp_word <= 32'hdead_0003;
                        end
                    end
                    OP_QUERY: begin
                        case (cmd_word[23:16])
                            8'h00: rsp_word <= {29'd0, tt_rd_status};
                            8'h01: rsp_word <= {28'd0, current_task};
                            8'h02: rsp_word <= {27'd0, pq_depth};
                            8'h03: rsp_word <= {27'd0, sq_depth};
                            8'h04: rsp_word <= 32'h0000_0000;
                            8'h05: rsp_word <= {24'd0, irq_reason};
                            8'h06: rsp_word <= tick_count;
                            8'h07: rsp_word <= {22'd0, sched_mode, flags_reg};
                            default: rsp_word <= 32'h0;
                        endcase
                    end
                    OP_SCAN: rsp_word <= 32'h0000_c00e;
                    OP_RESET: begin
                        if (cmd_word[23:16] == 8'had) begin
                            pq_flush <= 1'b1;
                            sq_flush <= 1'b1;
                            timer_enable <= 1'b0;
                            sched_mode <= 2'b00;
                            flags_reg <= 8'd0;
                            fast_mask <= 8'hff;
                            irq_n <= 1'b1;
                            irq_reason <= 8'd0;
                            current_task <= {ID_WIDTH{1'b1}};
                            tick_count <= 0;
                            pending_word2 <= 1'b0;
                            pending_opcode <= 4'd0;
                            pending_task_id <= 4'd0;
                            pending_word1 <= 32'd0;
                            tt_clear_all <= 1'b1;
                            rsp_word <= 32'h0000_c0ff;
                        end else begin
                            rsp_word <= 32'hdead_0001;
                        end
                    end
                    default: rsp_word <= 32'hdead_beef;
                endcase
            end

            if (sq_wake_valid) begin
                prep_tt_write(sq_wake_id);
                tt_wr_status <= 3'b010;
                tt_wr_remaining_wcet <= tt_rd_wcet; // reset for new period
                pq_enq_id <= sq_wake_id;
                pq_enqueue <= 1'b1;
                irq_n <= 1'b0;
                irq_reason <= 8'h04;
            end

            if (irq_pending) begin
                irq_n <= 1'b0;
                irq_reason <= fast_irq ? 8'h05 : 8'h06;
            end

            if (pq_head_valid && flags_reg[7] && (current_task != pq_head_id)) begin
                irq_n <= 1'b0;
                irq_reason <= 8'h01;
            end

            // Deadline miss fires last so it overrides all other IRQ sources.
            // Guard with !pending_word2 && !sq_wake_valid so tt_rd_id tracks running task
            // (lower-priority mux entries would redirect to a different task).
            if (tick_pulse && !pending_word2 && !sq_wake_valid &&
                current_task != {ID_WIDTH{1'b1}} && tt_rd_status == 3'b011 &&
                tick_count[15:0] + 16'd1 == tt_rd_abs_deadline) begin
                irq_n <= 1'b0;
                irq_reason <= 8'h03;
            end

        end
    end
endmodule
