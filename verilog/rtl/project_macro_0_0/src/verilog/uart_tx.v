//==============================================================================
//  Module      : uart_tx
//  Author      : Mohamed Tarek (Modified for continuous byte stream)
//  Date        : Nov 2025
//  Course      : NTI Verilog Course
//==============================================================================

`default_nettype none

module uart_tx (
    input  wire        clk,       // 100 MHz
    input  wire        arst_n,    // active low async reset
    input  wire        rst,       // active high sync soft reset CTRL REG
    input  wire        tx_en,     // enable signal CTRL REG
    input  wire [7:0]  tx_data,   // DATA REG
    input  wire [31:0] baudiv,    // BAUDDIV REG

    output reg         tx,
    output wire        tx_busy,   // STATUS REG
    output wire        tx_done
);

reg [31:0] counter;
reg [3:0]  bit_num;
reg [0:9]  frame;
reg [7:0]  data_rev;
integer i;

// Reverse the data bus
always @(*) begin
    for (i = 0; i < 8; i = i + 1)
        data_rev[7-i] = tx_data[i];
end

// Prepare UART frame {start, data, stop}
always @(posedge clk or negedge arst_n) begin
    if(!arst_n)
        frame <= 10'b0;
    else if(rst)
        frame <= 10'b0;
    else
        frame <= {1'b0, data_rev, 1'b1};
end

// Baud generation counter
always @(posedge clk or negedge arst_n) begin
    if(!arst_n)
        counter <= 0;
    else if(rst)
        counter <= 0;
    else if(counter == baudiv-1)
        counter <= 0;
    else if(tx_en)
        counter <= counter + 1;
end

// Bit counter
always @(posedge clk or negedge arst_n) begin
    if(!arst_n)
        bit_num <= 0;
    else if(rst)
        bit_num <= 0;
    else if(counter == baudiv-1)
        bit_num <= (bit_num == 9) ? 0 : bit_num + 1;
end

// TX output
always @(posedge clk or negedge arst_n) begin
    if(!arst_n)
        tx <= 0;
    else if(rst)
        tx <= 1;
    else if(tx_en)
        tx <= frame[bit_num];
end

// Status signals
assign tx_busy = !(bit_num == 9 & counter == baudiv-1);
assign tx_done = (bit_num == 9 & counter == baudiv-1);

endmodule

`default_nettype wire
