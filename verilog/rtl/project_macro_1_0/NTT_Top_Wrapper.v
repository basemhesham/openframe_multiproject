module NTT_Top_Wrapper (
`ifdef USE_POWER_PINS
    inout vccd1,
    inout vssd1,
`endif
    input  wire clk,
    input  wire rst_n,
    input  wire mosi,
    output wire miso,
    input  wire cs_n
);

    wire [7:0] spi_cmd;
    wire [15:0] spi_data_in;
    reg  [15:0] spi_data_out;
    wire spi_valid; 
    
    reg  start, mode;
    wire done;
    reg  ext_ram_we;
    reg  [7:0] ext_ram_addr;
    reg  [11:0] ext_ram_data_in;
    wire [11:0] ext_ram_data_out;

    // Purely synchronous internal serial bus
    SPI_Slave spi_inst (
        .clk(clk),
        .rst_n(rst_n),
        .mosi(mosi), 
        .miso(miso), 
        .cs_n(cs_n),
        .cmd_addr(spi_cmd), 
        .data_in(spi_data_in), 
        .data_out(spi_data_out), 
        .data_valid(spi_valid) 
    );

    NTT_Accelerator_Top core_inst (
        .clk(clk), 
        .rst_n(rst_n), 
        .start(start), 
        .mode(mode),
        .ext_ram_we(ext_ram_we), 
        .ext_ram_addr(ext_ram_addr), 
        .ext_ram_data_in(ext_ram_data_in), 
        .ext_ram_data_out(ext_ram_data_out), 
        .done(done)
    );

    // ---------------------------------------------------------
    // REGISTER MAP (Single System Clock)
    // ---------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start <= 0; 
            mode <= 0; 
            ext_ram_we <= 0; 
            ext_ram_addr <= 0; 
            ext_ram_data_in <= 0;
        end else begin
            start <= 0; 
            ext_ram_we <= 0; 
            
            if (spi_valid) begin
                case (spi_cmd[6:0])
                    7'h00: begin start <= spi_data_in[0]; mode <= spi_data_in[1]; end 
                    7'h02: ext_ram_addr <= spi_data_in[7:0];                          
                    7'h03: if (spi_cmd[7]) begin                                      
                               ext_ram_data_in <= spi_data_in[11:0];
                               ext_ram_we <= 1'b1;
                           end
                endcase
            end
        end
    end

    // ---------------------------------------------------------
    // Combinational Read Logic 
    // ---------------------------------------------------------
    always @* begin
        if (spi_cmd[7] == 1'b0) begin
            case (spi_cmd[6:0])
                7'h01:   spi_data_out = {15'b0, done};
                7'h03:   spi_data_out = {4'b0, ext_ram_data_out};
                default: spi_data_out = 16'h0000;
            endcase
        end else begin
            spi_data_out = 16'h0000;
        end
    end

endmodule