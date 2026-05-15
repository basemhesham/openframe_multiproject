// sorted sleep queue: entries ordered by countdown (smallest = wakes soonest)
// on each tick all non-zero counts decrement; any entry reaching 0 wakes
// only one wake fires per clock cycle, but if multiple entries expire in the
// same tick the subsequent ones wake on consecutive cycles without waiting
// for the next tick pulse (control_unit handles one sq_wake_valid per cycle)
//
// Single clocked process with blocking RAM updates: Yosys proc infers clean
// registers (split always @(*) + always_ff caused "multiple conflicting drivers"
// on cnt_mem in LibreLane YosysSynthChecks).
module sleep_queue #(parameter DEPTH = 16, parameter ID_WIDTH = 4, parameter CNT_WIDTH = 32) (
    input wire clk,
    input wire rst_n,
    input wire flush,
    input wire enqueue,
    input wire tick,
    input wire [ID_WIDTH-1:0] enq_id,
    input wire [CNT_WIDTH-1:0] enq_count,
    output reg wake_valid,
    output reg [ID_WIDTH-1:0] wake_id,
    output wire [$clog2(DEPTH+1)-1:0] depth
);
    reg [ID_WIDTH-1:0] id_mem [0:DEPTH-1];
    reg [CNT_WIDTH-1:0] cnt_mem [0:DEPTH-1];
    reg valid_mem [0:DEPTH-1];
    reg [$clog2(DEPTH+1)-1:0] depth_r;
    reg [$clog2(DEPTH+1)-1:0] depth_work;
    integer i;
    integer pos;

    assign depth = depth_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            depth_r <= 0;
            wake_valid <= 1'b0;
            wake_id <= {ID_WIDTH{1'b0}};
            for (i = 0; i < DEPTH; i = i + 1) begin
                id_mem[i] <= {ID_WIDTH{1'b0}};
                cnt_mem[i] <= {CNT_WIDTH{1'b0}};
                valid_mem[i] <= 1'b0;
            end
        end else if (flush) begin
            depth_r <= 0;
            wake_valid <= 1'b0;
            wake_id <= {ID_WIDTH{1'b0}};
            for (i = 0; i < DEPTH; i = i + 1) begin
                id_mem[i] <= {ID_WIDTH{1'b0}};
                cnt_mem[i] <= {CNT_WIDTH{1'b0}};
                valid_mem[i] <= 1'b0;
            end
        end else begin
            wake_valid <= 1'b0;
            depth_work = depth_r;

            // step 1: decrement all valid non-zero counters on tick
            if (tick) begin
                for (i = 0; i < DEPTH; i = i + 1) begin
                    if (valid_mem[i] && cnt_mem[i] != {CNT_WIDTH{1'b0}})
                        cnt_mem[i] = cnt_mem[i] - 1'b1;
                end
            end

            // step 2: wake head if its counter reached zero
            // fires every cycle — not gated by tick — so consecutive expirations
            // each produce a wake one cycle apart with no extra tick needed
            if (depth_work != 0 && valid_mem[0] && cnt_mem[0] == {CNT_WIDTH{1'b0}}) begin
                wake_valid <= 1'b1;
                wake_id <= id_mem[0];
                for (i = 0; i < DEPTH-1; i = i + 1) begin
                    if (i < depth_work - 1) begin
                        id_mem[i] = id_mem[i+1];
                        cnt_mem[i] = cnt_mem[i+1];
                        valid_mem[i] = valid_mem[i+1];
                    end
                end
                id_mem[depth_work-1] = {ID_WIDTH{1'b0}};
                cnt_mem[depth_work-1] = {CNT_WIDTH{1'b0}};
                valid_mem[depth_work-1] = 1'b0;
                depth_work = depth_work - 1'b1;
            end

            // step 3: sorted insert (ascending by count so head wakes soonest)
            if (enqueue && depth_work < DEPTH) begin
                pos = depth_work;
                for (i = 0; i < DEPTH; i = i + 1) begin
                    if (i < depth_work && enq_count < cnt_mem[i] && pos == depth_work)
                        pos = i;
                end
                for (i = DEPTH-1; i > 0; i = i - 1) begin
                    if (i > pos && i <= depth_work) begin
                        id_mem[i] = id_mem[i-1];
                        cnt_mem[i] = cnt_mem[i-1];
                        valid_mem[i] = valid_mem[i-1];
                    end
                end
                id_mem[pos] = enq_id;
                cnt_mem[pos] = enq_count;
                valid_mem[pos] = 1'b1;
                depth_work = depth_work + 1'b1;
            end

            depth_r <= depth_work;
        end
    end
endmodule
