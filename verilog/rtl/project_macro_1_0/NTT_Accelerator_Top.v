module NTT_Accelerator_Top #(
    parameter DATA_WIDTH = 12,
    parameter ADDR_WIDTH = 8,
    parameter [11:0] Q_PRIME = 12'd3329
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire mode,
    
    // Memory access ports (Exposed for external SPI loading)
    input  wire ext_ram_we,
    input  wire [ADDR_WIDTH-1:0] ext_ram_addr,
    input  wire [DATA_WIDTH-1:0] ext_ram_data_in,
    output wire [DATA_WIDTH-1:0] ext_ram_data_out,
    
    output wire done
);

    wire [ADDR_WIDTH-1:0] ram_addr_a, ram_addr_b, muxed_addr_a;
    wire [DATA_WIDTH-1:0] ram_dout_a, ram_dout_b, muxed_din_a;
    wire [DATA_WIDTH-1:0] ubu_out_a, ubu_out_b;
    wire ram_we, ubu_start, ubu_done, muxed_we_a;
    wire [6:0] twiddle_addr;
    wire [DATA_WIDTH-1:0] twiddle_factor;
    wire busy;

    // Multiplexer logic: Give RAM control to external SPI ONLY when NOT busy
    assign muxed_addr_a = busy ? ram_addr_a : ext_ram_addr;
    assign muxed_din_a  = busy ? ubu_out_a  : ext_ram_data_in;
    assign muxed_we_a   = busy ? ram_we     : ext_ram_we;
    
    assign ext_ram_data_out = ram_dout_a;

    Twiddle_ROM #(
        .DATA_WIDTH(DATA_WIDTH), 
        .ADDR_WIDTH(7)
    ) rom_inst (
        .addr(twiddle_addr),
        .twiddle(twiddle_factor)
    );

    NTT_RAM #(
        .DATA_WIDTH(DATA_WIDTH), 
        .ADDR_WIDTH(ADDR_WIDTH)
    ) memory_inst (
        .clk(clk),
        .ena(1'b1), 
        .wea(muxed_we_a), 
        .addra(muxed_addr_a), 
        .dina(muxed_din_a), 
        .douta(ram_dout_a),
        .enb(1'b1), 
        .web(ram_we),     
        .addrb(ram_addr_b),   
        .dinb(ubu_out_b),   
        .doutb(ram_dout_b)
    );

    U_Butterfly_Unit #(
        .DATA_WIDTH(DATA_WIDTH)
    ) ubu_inst (
        .clk(clk), 
        .rst_n(rst_n), 
        .start(ubu_start), 
        .mode(mode), 
        .q(Q_PRIME),
        .U_in(ram_dout_a), 
        .V_in(ram_dout_b), 
        .twiddle(twiddle_factor),
        .U_out(ubu_out_a), 
        .V_out(ubu_out_b), 
        .done(ubu_done)
    );

    NTT_Control_Unit #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) cu_inst (
        .clk(clk), 
        .rst_n(rst_n), 
        .start(start), 
        .ubu_done(ubu_done),
        .ram_addr_a(ram_addr_a), 
        .ram_addr_b(ram_addr_b), 
        .ram_we(ram_we),
        .ubu_start(ubu_start), 
        .twiddle_addr(twiddle_addr), 
        .done(done),
        .busy(busy) 
    );

endmodule