`timescale 1ns/1ps

module ecg_preprocessor_tb;

reg clk;
reg rst_n;
reg [7:0] adc_in;
reg adc_valid;
reg sample_received;

wire [7:0] shifted_out;
wire shifted_out_valid;
wire [7:0] peak1_val;
wire [7:0] rolling_min_out;
wire valid_pair_found;
wire tol_alarm_out;
wire rs_alarm_out;
wire max_win_alarm_out;

localparam [7:0] SLOPE_THR  = 8'd15;
localparam [7:0] RS_WIN     = 8'd80;
localparam [7:0] MAX_WIN    = 8'd50;
localparam [7:0] TOLERANCE  = 8'd40;
localparam [7:0] FLOOR_OFF  = 8'd10;

reg [7:0] mem [0:4093803];  // 21892 samples × 187 features                                                                                                
integer counter;

ecg_preprocessor dut (
    .clk(clk),
    .rst_n(rst_n),
    .adc_in(adc_in),
    .adc_valid(adc_valid),
    .sample_received(sample_received),
    .slope_thresh(SLOPE_THR),
    .rs_window(RS_WIN),
    .max_window(MAX_WIN),
    .tolerance(TOLERANCE),
    .floor_offset(FLOOR_OFF),
    .shifted_out(shifted_out),
    .shifted_out_valid(shifted_out_valid),
    .peak1_val(peak1_val),
    .rolling_min_out(rolling_min_out),
    .valid_pair_found(valid_pair_found),
    .tol_alarm_out(tol_alarm_out),
    .rs_alarm_out(rs_alarm_out),
    .max_win_alarm_out(max_win_alarm_out)
);

always #5 clk = ~clk;

task push_sample;
    input [7:0] v;
    begin
        @(posedge clk);
        adc_in <= v;
        adc_valid <= 1'b1;
        @(posedge clk);
        adc_valid <= 1'b0;
    end
endtask

task idle_cycles;
    input integer n;
    integer k;
    begin
        for (k = 0; k < n; k = k + 1) begin
            @(posedge clk);
        end
    end
endtask

integer i;
integer j;

initial begin
    $readmemh("ecg_data.mem", mem);
    clk = 1'b0;
    rst_n = 1'b0;
    adc_in = 8'd0;
    adc_valid = 1'b0;
    sample_received = 1'b0;

    idle_cycles(2);
    rst_n = 1'b1;
    repeat(3)
    begin
        for(i = 0; i < 187; i = i + 1) begin
            push_sample($floor(mem[i] * 0.25)); // Scale down the sample values to fit in 8 bits.
        end
    end
    /*
    // Fill buffer with 8 samples.
    for (i = 0; i < 8; i = i + 1) begin
        push_sample(8'd20 + i);
    end

    // Create first sharp slope event.
    push_sample(8'd40);
    push_sample(8'd38);
    push_sample(8'd35);
    push_sample(8'd20);
    push_sample(8'd15);
    push_sample(8'd60);

    // Backoff samples.
    for (i = 0; i < 8; i = i + 1) begin
        push_sample(8'd45 + i);
    end

    // Tracking samples then second slope near first peak to form valid pair.
    push_sample(8'd42);
    push_sample(8'd44);
    push_sample(8'd39);
    push_sample(8'd25);
    push_sample(8'd24);
    push_sample(8'd58);

    idle_cycles(4);

    if (valid_pair_found) begin
        $display("INFO: valid_pair_found pulse observed.");
    end

    // Kick the FSM out of WAIT.
    @(posedge clk);
    sample_received <= 1'b1;
    @(posedge clk);
    sample_received <= 1'b0;

    // Force rs alarm scenario by deep drop.
    push_sample(8'd50);
    push_sample(8'd48);
    push_sample(8'd47);
    push_sample(8'd20);
    push_sample(8'd18);
    push_sample(8'd68);

    for (i = 0; i < 8; i = i + 1) begin
        push_sample(8'd55);
    end

    push_sample(8'd10);
    push_sample(8'd9);
    push_sample(8'd8);

    idle_cycles(10);
    */
    idle_cycles(100); // Let the FSM process all samples and settle.

    $display("TB done. peak1=%0d rolling_min=%0d tol_alarm=%0b rs_alarm=%0b max_alarm=%0b",
             peak1_val, rolling_min_out, tol_alarm_out, rs_alarm_out, max_win_alarm_out);
    $stop;
end
integer k;
integer min;
integer max;

initial 
begin
    counter = 0;
    min = $floor(mem[0] * 0.25);
    max = $floor(mem[0] * 0.25);
    forever begin
        @(posedge clk);
        if(shifted_out_valid)
        begin
            counter = counter + 1;
            if(shifted_out != ($floor(mem[counter-1] * 0.25))) begin
                $display("ERROR: shifted_out mismatch at sample %0d. Expected %0d, got %0d @%0t",
                         counter, $floor(mem[counter -1] * 0.25), shifted_out, $time);
            end
            if(counter == 187) begin
                $display("INFO: All samples shifted out.");
                for(k = 0; k < 187; k = k + 1) 
                begin
                    if($floor(mem[k] * 0.25) < min) begin
                        min = $floor(mem[k] * 0.25);
                    end
                    if($floor(mem[k] * 0.25) > max) begin
                        max = $floor(mem[k] * 0.25);
                    end
                end
                $display("INFO: Minimum sample value is %0d while output is %0d", min, rolling_min_out);
                $display("INFO: Maximum sample value is %0d while peak1_val is %0d", max, peak1_val);
                counter = 0;
            end
        end
    end
end

endmodule
