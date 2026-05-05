// TraceGuard-X ASIC — AUC Silicon Sprint
// Module : pattern_sram
// Process: SKY130 Open PDK
// Authors: Omar Ahmed Fouad, Ahmed Tawfiq, Omar Ahmed Abdelaty
//
// RTL source — see docs/report/ for full module specification.

module pattern_sram #(
    parameter MAX_STATES = 16,  
    parameter WIDTH      = 8    
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [8:0]  addr,     
    input  wire [7:0]  data_in,
    input  wire        wr_en,
    input  wire        rd_en,
    output reg  [7:0]  data_out,
    output wire        busy      
);

 
    localparam MAX_PATTERN_LEN = MAX_STATES - 1; 

    localparam TOTAL_DEPTH     = 2 + MAX_PATTERN_LEN; 


    reg [WIDTH-1:0] pattern_regs [0:TOTAL_DEPTH-1];


    assign busy = 1'b0;
    
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < TOTAL_DEPTH; i = i + 1) begin
                pattern_regs[i] <= {WIDTH{1'b0}};
            end
            data_out <= {WIDTH{1'b0}};
        end else begin
            

            if (wr_en && (addr < TOTAL_DEPTH)) begin
                pattern_regs[addr] <= data_in;
            end
            

            if (rd_en) begin
                if (addr < TOTAL_DEPTH)
                    data_out <= pattern_regs[addr];
                else
                    data_out <= {WIDTH{1'b0}}; 
            end
        end
    end

endmodule
