module SPI_Slave (
    input  wire clk,     // System Clock
    input  wire rst_n,
    
    input  wire mosi,    // Synchronous Master Out
    output reg  miso,    // Synchronous Slave Out
    input  wire cs_n,    // Active low transaction frame
    
    output reg  [7:0] cmd_addr,
    output reg  [15:0] data_in,
    input  wire [15:0] data_out,
    output reg  data_valid
);

    reg [4:0] counter;
    reg [23:0] shift_reg;

    // ---------------------------------------------------------
    // Synchronous Shift-In (MOSI) & Command Logic
    // ---------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter    <= 5'd0;
            shift_reg  <= 24'd0;
            cmd_addr   <= 8'd0;
            data_in    <= 16'd0;
            data_valid <= 1'b0;
        end else begin
            // Default pulse state
            data_valid <= 1'b0; 
            
            if (cs_n) begin
                counter <= 5'd0; // Reset transaction
            end else begin
                // Shift 1 bit every single clock cycle
                shift_reg <= {shift_reg[22:0], mosi};
                counter   <= counter + 1'b1;
                
                // Capture command exactly after 8 bits
                if (counter == 5'd7) begin
                    cmd_addr <= {shift_reg[6:0], mosi};
                end
                
                // Assert valid and capture payload after 24 bits
                if (counter == 5'd23) begin
                    data_in    <= {shift_reg[14:0], mosi};
                    data_valid <= 1'b1; 
                end
            end
        end
    end

    // ---------------------------------------------------------
    // Synchronous Shift-Out (MISO)
    // ---------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            miso <= 1'b0;
        end else if (cs_n) begin
            miso <= 1'b0; // Output 0 when inactive
        end else begin
            // Drive MISO so the Master can sample it on the next cycle
            if (counter >= 5'd7 && counter <= 5'd22) begin
                miso <= data_out[5'd22 - counter];
            end else begin
                miso <= 1'b0;
            end
        end
    end

endmodule