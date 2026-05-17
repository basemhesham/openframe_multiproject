`define ASIC
module ecg_top (
    input   wire clk,
    input   wire rstn,
    input   wire adc_in,
    output   wire tx,
    input    wire rx
);
    
ecg_wrapper #(
.BAUDIV(86),
.DATA_W(8)
) (
    clk,     // system clock (matches BAUDIV)
    arst_n,  // async reset, active low
    rx,      // UART RX pin (connect to host TX)
    tx,       // UART TX pin (connect to host RX)
    adc_valid,
    adc_data,
    adc_ready
);
// ============================================================
// ADC instance
// ============================================================
`ifdef ADC_BD
    wire [7:0] adc_bd_data;
    wire       adc_bd_valid;
    ADC_bd_wrapper adc_inst (
        .adc_clk    (clk),
        .aresetn_0  (rst_n),
        .ready_in_0 (command_valid),
        .data_out_0 (adc_bd_data),
        .valid_out_0(adc_bd_valid)
    );
    assign adc_valid    = adc_bd_valid;
    assign adc_in_data  = {4'b0000, adc_bd_data};
    assign command_ready = 1'b1;
`elsif DE10
    adc adc_inst (
        .adc_pll_clock_clk      (adc_pll_clock_clk),
        .adc_pll_locked_export  (adc_pll_locked_export),
        .clock_clk              (clk),
        .reset_sink_reset_n     (rst_n),
        .command_valid          (command_valid),
        .command_channel        (5'd0),
        .command_startofpacket  (command_startofpacket),
        .command_endofpacket    (command_endofpacket),
        .command_ready          (command_ready),
        .response_valid         (adc_valid),
        .response_channel       (),
        .response_data          (adc_in_data),
        .response_startofpacket (),
        .response_endofpacket   ()
    );
    
`elsif ASIC
 tt_um_TT06_SAR_wulffern u_adc (
`ifdef USE_POWER_PINS
        .VPWR    (vccd1),
        .VGND    (vssd1),
`endif
        .clk     (clk),
        .rst_n   (rstn),
        .ena     (1'b1),
        .ui_in   (gpio_bot_in),
        .uo_out  (adc_uo_out),
        .uio_in  (8'b0),
        .uio_out (adc_uio_out),
        .uio_oe  (adc_uio_oe),
        .ua      (ua_nc)
    );    
`endif




endmodule 