// pipeline priority queue cell
// pass outputs are combinational so the full chain settles in one clock cycle
// simultaneous dequeue+enqueue: dequeue (shift from right) then insert incoming
module pq_cell #(
    parameter ID_WIDTH = 4,
    parameter KEY_WIDTH = 16
) (
    input wire clk,
    input wire rst_n,
    input wire enqueue,
    input wire dequeue,
    input wire flush,
    input wire [ID_WIDTH-1:0] in_id,
    input wire [KEY_WIDTH-1:0] in_key,
    input wire in_valid,
    input wire [ID_WIDTH-1:0] right_id,
    input wire [KEY_WIDTH-1:0] right_key,
    input wire right_valid,
    output reg [ID_WIDTH-1:0] cell_id,
    output reg [KEY_WIDTH-1:0] cell_key,
    output reg cell_valid,
    output wire [ID_WIDTH-1:0] pass_id,
    output wire [KEY_WIDTH-1:0] pass_key,
    output wire pass_valid
);
    // incoming beats current cell (enqueue-only path)
    wire in_beats_cell = in_valid && (!cell_valid || in_key > cell_key);
    // incoming beats right neighbor (deq+enq combined path: cell effectively holds right after shift)
    wire in_beats_right = in_valid && (!right_valid || in_key > right_key);

    // pass is combinational, needed so the insertion ripple settles within a single clock cycle
    assign pass_valid = enqueue ? (dequeue ? (in_beats_right ? right_valid : in_valid) : (in_beats_cell ? cell_valid : in_valid)) : 1'b0;
    assign pass_id = dequeue ? (in_beats_right ? right_id : in_id) : (in_beats_cell ? cell_id : in_id);
    assign pass_key = dequeue ? (in_beats_right ? right_key : in_key) : (in_beats_cell ? cell_key : in_key);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cell_id <= {ID_WIDTH{1'b0}};
            cell_key <= {KEY_WIDTH{1'b0}};
            cell_valid <= 1'b0;
        end else if (flush) begin
            cell_id <= {ID_WIDTH{1'b0}};
            cell_key <= {KEY_WIDTH{1'b0}};
            cell_valid <= 1'b0;
        end else if (dequeue && enqueue) begin
            // logically: shift from right first, then compete with incoming item
            if (in_beats_right) begin
                cell_id <= in_id;
                cell_key <= in_key;
                cell_valid <= in_valid;
            end else begin
                cell_id <= right_id;
                cell_key <= right_key;
                cell_valid <= right_valid;
            end
        end else if (dequeue) begin
            cell_id <= right_id;
            cell_key <= right_key;
            cell_valid <= right_valid;
        end else if (enqueue) begin
            if (in_beats_cell) begin
                cell_id <= in_id;
                cell_key <= in_key;
                cell_valid <= in_valid;
            end
            // cell wins: content unchanged, incoming item propagates right via pass
        end
    end
endmodule
