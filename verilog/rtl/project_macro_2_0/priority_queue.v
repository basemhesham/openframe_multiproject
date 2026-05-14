// sorted priority queue built from a chain of pq_cell instances
// head (index 0) always holds the highest-key item
// enqueue: O(DEPTH) combinational ripple, 1-cycle latency
// dequeue: all cells shift left simultaneously, 1-cycle latency
// simultaneous enqueue+dequeue supported (net depth unchanged)
module priority_queue #(
    parameter DEPTH = 16,
    parameter ID_WIDTH = 4,
    parameter KEY_WIDTH = 16
) (
    input wire clk,
    input wire rst_n,
    input wire enqueue,
    input wire dequeue,
    input wire flush,
    input wire [ID_WIDTH-1:0] enq_id,
    input wire [KEY_WIDTH-1:0] enq_key,
    output wire [ID_WIDTH-1:0] head_id,
    output wire [KEY_WIDTH-1:0] head_key,
    output wire head_valid,
    output wire [$clog2(DEPTH+1)-1:0] depth
);
    reg [$clog2(DEPTH+1)-1:0] depth_r;

    // guard against overflow / underflow before asserting to cells
    wire enq_valid = enqueue && (depth_r < DEPTH[$clog2(DEPTH+1)-1:0]);
    wire deq_valid = dequeue && (depth_r != {($clog2(DEPTH+1)){1'b0}});

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            depth_r <= {($clog2(DEPTH+1)){1'b0}};
        end else if (flush) begin
            depth_r <= {($clog2(DEPTH+1)){1'b0}};
        end else begin
            case ({enq_valid, deq_valid})
                2'b10: depth_r <= depth_r + 1'b1;
                2'b01: depth_r <= depth_r - 1'b1;
                default: ;
            endcase
        end
    end

    assign depth = depth_r;

    // inter-cell wires: cell outputs and pass outputs per slot
    wire [ID_WIDTH-1:0] cell_id_w [0:DEPTH-1];
    wire [KEY_WIDTH-1:0] cell_key_w [0:DEPTH-1];
    wire cell_valid_w [0:DEPTH-1];
    wire [ID_WIDTH-1:0] pass_id_w [0:DEPTH-1];
    wire [KEY_WIDTH-1:0] pass_key_w [0:DEPTH-1];
    wire pass_valid_w [0:DEPTH-1];

    // muxed inputs per cell (avoids out-of-bounds index in generate ternaries)
    wire [ID_WIDTH-1:0] in_id_w [0:DEPTH-1];
    wire [KEY_WIDTH-1:0] in_key_w [0:DEPTH-1];
    wire in_valid_w [0:DEPTH-1];
    wire [ID_WIDTH-1:0] right_id_w [0:DEPTH-1];
    wire [KEY_WIDTH-1:0] right_key_w [0:DEPTH-1];
    wire right_valid_w [0:DEPTH-1];

    // cell 0 takes enqueue inputs
    assign in_id_w[0] = enq_id;
    assign in_key_w[0] = enq_key;
    assign in_valid_w[0] = enq_valid;

    // last cell has no right neighbor
    assign right_id_w[DEPTH-1] = {ID_WIDTH{1'b0}};
    assign right_key_w[DEPTH-1] = {KEY_WIDTH{1'b0}};
    assign right_valid_w[DEPTH-1] = 1'b0;

    genvar i;
    generate
        for (i = 1; i < DEPTH; i = i + 1) begin : g_in
            assign in_id_w[i] = pass_id_w[i-1];
            assign in_key_w[i] = pass_key_w[i-1];
            assign in_valid_w[i] = pass_valid_w[i-1];
        end
        for (i = 0; i < DEPTH-1; i = i + 1) begin : g_right
            assign right_id_w[i] = cell_id_w[i+1];
            assign right_key_w[i] = cell_key_w[i+1];
            assign right_valid_w[i] = cell_valid_w[i+1];
        end
        for (i = 0; i < DEPTH; i = i + 1) begin : g_cells
            pq_cell #(
                .ID_WIDTH(ID_WIDTH),
                .KEY_WIDTH(KEY_WIDTH)
            ) u_cell (
                .clk(clk),
                .rst_n(rst_n),
                .enqueue(enq_valid),
                .dequeue(deq_valid),
                .flush(flush),
                .in_id(in_id_w[i]),
                .in_key(in_key_w[i]),
                .in_valid(in_valid_w[i]),
                .right_id(right_id_w[i]),
                .right_key(right_key_w[i]),
                .right_valid(right_valid_w[i]),
                .cell_id(cell_id_w[i]),
                .cell_key(cell_key_w[i]),
                .cell_valid(cell_valid_w[i]),
                .pass_id(pass_id_w[i]),
                .pass_key(pass_key_w[i]),
                .pass_valid(pass_valid_w[i])
            );
        end
    endgenerate

    assign head_id = cell_id_w[0];
    assign head_key = cell_key_w[0];
    assign head_valid = cell_valid_w[0];

    // packed debug vectors so testbenches can probe cell state without
    // using a runtime variable to index into a generate block hierarchy
    wire [DEPTH-1:0] dbg_cell_valid;
    wire [ID_WIDTH*DEPTH-1:0] dbg_cell_id;
    wire [KEY_WIDTH*DEPTH-1:0] dbg_cell_key;
    genvar k;
    generate
        for (k = 0; k < DEPTH; k = k + 1) begin : g_dbg
            assign dbg_cell_valid[k] = cell_valid_w[k];
            assign dbg_cell_id[ID_WIDTH*k +: ID_WIDTH] = cell_id_w[k];
            assign dbg_cell_key[KEY_WIDTH*k +: KEY_WIDTH] = cell_key_w[k];
        end
    endgenerate
endmodule