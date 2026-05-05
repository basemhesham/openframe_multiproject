// TraceGuard-X ASIC — AUC Silicon Sprint
// Module : score_unit
// Process: SKY130 Open PDK
// Authors: Omar Ahmed Fouad, Ahmed Tawfiq, Omar Ahmed Abdelaty
//
// RTL source — see docs/report/ for full module specification.

module score_unit (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,

    // from AC engine
    input  wire [7:0] match_count,
    input  wire [7:0] confidence,
    input  wire [2:0] last_pattern_id,
    input  wire       ac_done,
    input  wire       hold_alert, 

    // configuration & metadata
    input  wire [7:0] threshold,
    input  wire       threshold_wr,
    input  wire [4:0] window_size,

    // outputs
    output reg  [7:0] score,
    output reg        alert_flag,
    output reg        match_flag,
    output wire       processing
);

    wire _unused = &{1'b0, confidence, last_pattern_id};

    reg [7:0]  threshold_r;
    reg        processing_q;
    reg [15:0] mult_reg;
    reg [7:0]  match_latched;

    wire [5:0] eff_size = (window_size == 5'd0) ? 6'd32 : {1'b0, window_size};
    assign processing = ac_done | processing_q;

    // Reciprocal Lookup Table
    wire [15:0] inv_table [0:63];
    genvar i;
    generate
        wire [15:0] const_255 = {8'h00, 8'hFF};
        assign inv_table[0] = const_255;
        for (i = 1; i < 64; i = i + 1) begin : gen_inv_table
            assign inv_table[i] = 16'd65280 / i;
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) threshold_r <= 8'd200;
        else if (threshold_wr) threshold_r <= threshold;
    end

    wire [7:0] unused_mult = mult_reg[7:0];
    wire [7:0] score_next_val = mult_reg[15:8];

    wire [15:0] match_count_ext = {8'h00, match_count};
    wire [31:0] mult_val_full   = match_count_ext * inv_table[eff_size];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {processing_q, alert_flag, match_flag} <= 3'd0;
            {score, match_latched} <= 16'd0;
            mult_reg <= 16'd0;
        end else if (en) begin
            processing_q <= ac_done;
            if (ac_done) begin
                match_latched <= match_count;
                mult_reg      <= mult_val_full[15:0];
            end

            if (processing_q) begin
                score      <= score_next_val;
                match_flag <= (match_latched > 0);
                // Trigger alert ONLY if score is below threshold
                alert_flag <= (score_next_val < threshold_r) ? 1'b1 : 1'b0;
            end else if (hold_alert) begin
                // FIX: Instantly clear everything during tracking window
                alert_flag <= 1'b0;
                match_flag <= 1'b0;
                score      <= 8'd0; 
            end
        end
    end
endmodule
