module NTT_RAM #(
    parameter DATA_WIDTH = 12,
    parameter ADDR_WIDTH = 8  
)(
    input  wire clk,
    input  wire ena,
    input  wire wea,
    input  wire [ADDR_WIDTH-1:0] addra,
    input  wire [DATA_WIDTH-1:0] dina,
    output reg  [DATA_WIDTH-1:0] douta,
    
    input  wire enb,
    input  wire web,
    input  wire [ADDR_WIDTH-1:0] addrb,
    input  wire [DATA_WIDTH-1:0] dinb,
    output reg  [DATA_WIDTH-1:0] doutb
);

    reg [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];

    always @(posedge clk) begin
        if (ena) begin
            if (wea) begin
                ram[addra] <= dina;
            end
            douta <= ram[addra];
        end
        
        if (enb) begin
            if (web) begin
                ram[addrb] <= dinb;
            end
            doutb <= ram[addrb];
        end
    end

endmodule