module task_table #(parameter NUM_TASKS = 16, parameter ID_WIDTH = 4) (
    input wire clk,
    input wire rst_n,
    input wire clear_all,
    input wire wr_en,
    input wire [ID_WIDTH-1:0] wr_id,
    input wire [3:0] wr_priority,
    input wire [15:0] wr_period,
    input wire [15:0] wr_deadline,
    input wire [15:0] wr_wcet,
    input wire wr_type,
    input wire wr_preemptable,
    input wire [2:0] wr_status,
    input wire [15:0] wr_abs_deadline,
    input wire [15:0] wr_remaining_wcet,
    input wire rd_en,
    input wire [ID_WIDTH-1:0] rd_id,
    output reg [3:0] rd_priority,
    output reg [15:0] rd_period,
    output reg [15:0] rd_deadline,
    output reg [15:0] rd_wcet,
    output reg rd_type,
    output reg rd_preemptable,
    output reg [2:0] rd_status,
    output reg [15:0] rd_abs_deadline,
    output reg [15:0] rd_remaining_wcet
);

    reg [3:0] priority_mem [0:NUM_TASKS-1];
    reg [15:0] period_mem [0:NUM_TASKS-1];
    reg [15:0] deadline_mem [0:NUM_TASKS-1];
    reg [15:0] wcet_mem [0:NUM_TASKS-1];
    reg type_mem [0:NUM_TASKS-1];
    reg pre_mem [0:NUM_TASKS-1];
    reg [2:0] status_mem [0:NUM_TASKS-1];
    reg [15:0] abs_deadline_mem [0:NUM_TASKS-1];
    reg [15:0] remaining_wcet_mem [0:NUM_TASKS-1];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_TASKS; i = i + 1) begin
                priority_mem[i] <= 0;
                period_mem[i] <= 0;
                deadline_mem[i] <= 0;
                wcet_mem[i] <= 0;
                type_mem[i] <= 0;
                pre_mem[i] <= 0;
                status_mem[i] <= 3'b000;
                abs_deadline_mem[i] <= 0;
                remaining_wcet_mem[i] <= 0;
            end
        end else if (clear_all) begin
            for (i = 0; i < NUM_TASKS; i = i + 1) begin
                priority_mem[i] <= 0;
                period_mem[i] <= 0;
                deadline_mem[i] <= 0;
                wcet_mem[i] <= 0;
                type_mem[i] <= 0;
                pre_mem[i] <= 0;
                status_mem[i] <= 3'b000;
                abs_deadline_mem[i] <= 0;
                remaining_wcet_mem[i] <= 0;
            end
        end else if (wr_en) begin
            priority_mem[wr_id] <= wr_priority;
            period_mem[wr_id] <= wr_period;
            deadline_mem[wr_id] <= wr_deadline;
            wcet_mem[wr_id] <= wr_wcet;
            type_mem[wr_id] <= wr_type;
            pre_mem[wr_id] <= wr_preemptable;
            status_mem[wr_id] <= wr_status;
            abs_deadline_mem[wr_id] <= wr_abs_deadline;
            remaining_wcet_mem[wr_id] <= wr_remaining_wcet;
        end
    end

    always @(*) begin
        if (rd_en) begin
            rd_priority = priority_mem[rd_id];
            rd_period = period_mem[rd_id];
            rd_deadline = deadline_mem[rd_id];
            rd_wcet = wcet_mem[rd_id];
            rd_type = type_mem[rd_id];
            rd_preemptable = pre_mem[rd_id];
            rd_status = status_mem[rd_id];
            rd_abs_deadline = abs_deadline_mem[rd_id];
            rd_remaining_wcet = remaining_wcet_mem[rd_id];
        end else begin
            rd_priority = 0;
            rd_period = 0;
            rd_deadline = 0;
            rd_wcet = 0;
            rd_type = 0;
            rd_preemptable = 0;
            rd_status = 0;
            rd_abs_deadline = 0;
            rd_remaining_wcet = 0;
        end
    end
endmodule
