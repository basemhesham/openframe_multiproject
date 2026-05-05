`default_nettype none

module project_macro (
`ifdef USE_POWER_PINS
    inout vccd1,
    inout vssd1,
`endif
    // From green macro (left edge)
    input  wire        clk,
    input  wire        reset_n,
    input  wire        por_n,

    // Bottom GPIOs (15)
    input  wire [14:0] gpio_bot_in,
    output wire [14:0] gpio_bot_out,
    output wire [14:0] gpio_bot_oeb,
    output wire [44:0] gpio_bot_dm,

    // Right GPIOs (9)
    input  wire [8:0]  gpio_rt_in,
    output wire [8:0]  gpio_rt_out,
    output wire [8:0]  gpio_rt_oeb,
    output wire [26:0] gpio_rt_dm,

    // Top GPIOs (14)
    input  wire [13:0] gpio_top_in,
    output wire [13:0] gpio_top_out,
    output wire [13:0] gpio_top_oeb,
    output wire [41:0] gpio_top_dm
);

    // ============================================================
    // ProxCore — LiDAR Safety Co-Processor
    // ============================================================
    //
    // GPIO Pin Assignment:
    //   gpio_bot[0]  — uart_rx       (input)   LiDAR sensor UART
    //   gpio_bot[1]  — spi_csn       (input)   SPI chip select
    //   gpio_bot[2]  — spi_sck       (input)   SPI clock
    //   gpio_bot[3]  — spi_mosi      (input)   SPI data in
    //   gpio_bot[4]  — brake_irq     (output)  Brake interrupt to CPU
    //   gpio_bot[5]  — fir_valid     (output)  Debug: filtered valid
    //   gpio_bot[6:14] — unused
    //   gpio_rt[8:0]   — unused
    //   gpio_top[13:0] — unused
    // ============================================================

    // Internal signals from ProxCore core
    wire        brake_irq_int;
    wire [15:0] dbg_filtered_out;
    wire        dbg_filtered_valid;
    wire [15:0] dbg_raw_distance;
    wire        dbg_raw_valid;

    // ============================================================
    // ProxCore Core Instantiation (with runtime baud rate control)
    // ============================================================
    proxcore_top #(
        .CLK_FREQ_HZ (25_000_000),
        .DEFAULT_THRESHOLD (16'd2560),
        .DEFAULT_BAUD_DIV  (16'd108)
    ) u_proxcore (
        .clk                (clk),
        .rst_n              (reset_n),        // template provides reset_n
        .uart_rx            (gpio_bot_in[0]),
        .spi_csn            (gpio_bot_in[1]),
        .spi_sck            (gpio_bot_in[2]),
        .spi_mosi           (gpio_bot_in[3]),
        .brake_irq          (brake_irq_int),
        .dbg_filtered_out   (dbg_filtered_out),
        .dbg_filtered_valid (dbg_filtered_valid),
        .dbg_raw_distance   (dbg_raw_distance),
        .dbg_raw_valid      (dbg_raw_valid)
    );

    // ============================================================
    // Bottom GPIO (15 pins)
    // ============================================================
    // Pins 0–3: inputs (uart_rx, spi_csn, spi_sck, spi_mosi)
    // Pin 4: output (brake_irq)
    // Pin 5: output (debug filtered_valid)
    // Pins 6–14: unused (safe tie-off)

    assign gpio_bot_out[3:0]   = 4'b0;                // inputs — drive zero
    assign gpio_bot_out[4]     = brake_irq_int;        // brake interrupt
    assign gpio_bot_out[5]     = dbg_filtered_valid;   // debug output
    assign gpio_bot_out[14:6]  = 9'b0;                 // unused

    assign gpio_bot_oeb[3:0]   = 4'b1111;             // inputs: oeb=1
    assign gpio_bot_oeb[4]     = 1'b0;                 // brake_irq: oeb=0 (output)
    assign gpio_bot_oeb[5]     = 1'b0;                 // debug: oeb=0 (output)
    assign gpio_bot_oeb[14:6]  = {9{1'b1}};           // unused: oeb=1 (safe)

    // ============================================================
    // Right GPIO (9 pins) — all unused
    // ============================================================
    assign gpio_rt_out = 9'b0;
    assign gpio_rt_oeb = {9{1'b1}};

    // ============================================================
    // Top GPIO (14 pins) — all unused
    // ============================================================
    assign gpio_top_out = 14'b0;
    assign gpio_top_oeb = {14{1'b1}};

    // ============================================================
    // Drive Modes — 3'b110 = strong push-pull for all pads
    // ============================================================
    // Input pads (bot 0–3): 3'b001 = input only, no pull
    // Output pads (bot 4–5): 3'b110 = strong push-pull
    // Unused pads: 3'b110 = strong push-pull (safe default)

    genvar i;
    generate
        // Bottom: pins 0–3 as input mode
        for (i = 0; i < 4; i = i + 1) begin : gen_bot_dm_in
            assign gpio_bot_dm[i*3 +: 3] = 3'b001;
        end
        // Bottom: pins 4–5 as output mode
        for (i = 4; i < 6; i = i + 1) begin : gen_bot_dm_out
            assign gpio_bot_dm[i*3 +: 3] = 3'b110;
        end
        // Bottom: pins 6–14 unused (default push-pull)
        for (i = 6; i < 15; i = i + 1) begin : gen_bot_dm_unused
            assign gpio_bot_dm[i*3 +: 3] = 3'b110;
        end

        // Right: all unused
        for (i = 0; i < 9; i = i + 1) begin : gen_rt_dm
            assign gpio_rt_dm[i*3 +: 3] = 3'b110;
        end

        // Top: all unused
        for (i = 0; i < 14; i = i + 1) begin : gen_top_dm
            assign gpio_top_dm[i*3 +: 3] = 3'b110;
        end
    endgenerate

endmodule
