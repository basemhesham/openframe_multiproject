// OpenFrame project_macro wrapper for HARTS (hw_scheduler_top)
//
// GPIO assignment:
//   gpio_rt_in[0]   -> uart_rx
//   gpio_rt_in[1]   -> scan_en
//   gpio_rt_in[2]   -> scan_in
//   gpio_rt_out[3]  -> uart_tx  (oeb=0)
//   gpio_rt_out[4]  -> irq_n    (oeb=0)
//   gpio_rt_out[5]  -> scan_out (oeb=0)
//   gpio_rt[8:6]    -> high-Z
//   gpio_bot_in[7:0]-> ext_irq[7:0]
//   gpio_bot[14:8]  -> high-Z
//   gpio_top        -> high-Z
//
// clk_freq = 20 MHz, baud = 115200 → UART_DIVISOR = 20e6/(115200*16) ≈ 11
module project_macro (
`ifdef USE_POWER_PINS
    inout vccd1,
    inout vssd1,
`endif
    input wire clk,
    input wire reset_n,
    input wire por_n,

    // Bottom GPIO (15 pads)
    input wire [14:0] gpio_bot_in,
    output wire [14:0] gpio_bot_out,
    output wire [14:0] gpio_bot_oeb,
    output wire [44:0] gpio_bot_dm,

    // Right GPIO (9 pads)
    input wire [8:0] gpio_rt_in,
    output wire [8:0] gpio_rt_out,
    output wire [8:0] gpio_rt_oeb,
    output wire [26:0] gpio_rt_dm,

    // Top GPIO (14 pads)
    input wire [13:0] gpio_top_in,
    output wire [13:0] gpio_top_out,
    output wire [13:0] gpio_top_oeb,
    output wire [41:0] gpio_top_dm
);

    // HARTS signals — inputs from rt_in[2:0], outputs to rt_out[5:3]
    wire uart_rx   = gpio_rt_in[0];
    wire scan_en   = gpio_rt_in[1];
    wire scan_in_w = gpio_rt_in[2];

    wire uart_tx_w;
    wire irq_n_w;
    wire scan_out_w;

    wire [7:0] ext_irq = gpio_bot_in[7:0];

    hw_scheduler_top #(
        .UART_DIVISOR(16'd11)
    ) u_harts (
        .clk      (clk),
        .rst_n    (reset_n),
        .uart_rx  (uart_rx),
        .uart_tx  (uart_tx_w),
        .ext_irq  (ext_irq),
        .irq_n    (irq_n_w),
        .scan_en  (scan_en),
        .scan_in  (scan_in_w),
        .scan_out (scan_out_w)
    );

    // Right GPIO
    // bits 0-2: inputs (oeb=1), bits 3-5: outputs (oeb=0), bits 6-8: high-Z (oeb=1)
    assign gpio_rt_out[2:0] = 3'b0;
    assign gpio_rt_out[3]   = uart_tx_w;
    assign gpio_rt_out[4]   = irq_n_w;
    assign gpio_rt_out[5]   = scan_out_w;
    assign gpio_rt_out[8:6] = 3'b0;

    assign gpio_rt_oeb = 9'b111_000_111;   // [5:3]=output, rest=input/high-Z
    assign gpio_rt_dm  = {9{3'b110}};

    // Bottom GPIO: ext_irq inputs on bits [7:0], all outputs high-Z
    assign gpio_bot_out = 15'b0;
    assign gpio_bot_oeb = 15'h7FFF;        // all pads input/high-Z
    assign gpio_bot_dm  = {15{3'b110}};

    // Top GPIO: all high-Z
    assign gpio_top_out = 14'b0;
    assign gpio_top_oeb = 14'h3FFF;
    assign gpio_top_dm  = {14{3'b110}};

endmodule
