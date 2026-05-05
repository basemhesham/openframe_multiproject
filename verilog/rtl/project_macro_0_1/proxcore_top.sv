module proxcore_top #(
    parameter int unsigned CLK_FREQ_HZ = 25_000_000,
    parameter logic [15:0] DEFAULT_THRESHOLD = 16'd2560,
    parameter logic [15:0] DEFAULT_COEFF    = 16'h0800,
    parameter logic [15:0] DEFAULT_BAUD_DIV  = 16'd108
) (
    // System
    input  logic        clk,
    input  logic        rst_n,

    // LiDAR UART interface (1 pin)
    input  logic        uart_rx,

    // SPI configuration interface (3 pins)
    input  logic        spi_csn,
    input  logic        spi_sck,
    input  logic        spi_mosi,

    // Brake interrupt output (1 pin)
    output logic        brake_irq,

    // Debug outputs (optional — useful for integration TB and ILA)
    output logic [15:0] dbg_filtered_out,
    output logic        dbg_filtered_valid,
    output logic [15:0] dbg_raw_distance,
    output logic        dbg_raw_valid
);

    // ----------------------------------------------------------------
    // Internal signals
    // ----------------------------------------------------------------

    // Deserializer → FIR filter
    logic [15:0] deser_data;
    logic        deser_valid;

    // FIR filter → Threshold FSM
    logic [15:0] fir_out;
    logic        fir_valid;

    // Config registers → FIR filter + Threshold FSM + Deserializer
    logic [15:0] cfg_threshold;
    logic [15:0] cfg_coeff0;
    logic [15:0] cfg_coeff1;
    logic [15:0] cfg_coeff2;
    logic [15:0] cfg_coeff3;
    logic [15:0] cfg_coeff4;
    logic [15:0] cfg_coeff5;
    logic [15:0] cfg_coeff6;
    logic [15:0] cfg_coeff7;
    logic [15:0] baud_div_w;

    // ----------------------------------------------------------------
    // Debug port assignments
    // ----------------------------------------------------------------
    assign dbg_filtered_out   = fir_out;
    assign dbg_filtered_valid = fir_valid;
    assign dbg_raw_distance   = deser_data;
    assign dbg_raw_valid      = deser_valid;

    // ----------------------------------------------------------------
    // Block 1: UART Deserializer (runtime-configurable baud rate)
    // Receives 16-bit distance words from LiDAR sensor
    // ----------------------------------------------------------------
    deserializer_gc u_deserializer (
        .clk        (clk),
        .rst_n      (rst_n),
        .rx         (uart_rx),
        .baud_div   (baud_div_w),
        .data_out   (deser_data),
        .data_valid (deser_valid)
    );

    // ----------------------------------------------------------------
    // Block 2: Pipelined Symmetric FIR Filter
    // 16-tap Hamming-windowed lowpass, 8 unique coefficients
    // ----------------------------------------------------------------
    proxcore_fir_filter u_fir (
        .clk          (clk),
        .rst_n        (rst_n),
        .sample_in    (deser_data),
        .sample_valid (deser_valid),
        .coeff_in0    (cfg_coeff0),
        .coeff_in1    (cfg_coeff1),
        .coeff_in2    (cfg_coeff2),
        .coeff_in3    (cfg_coeff3),
        .coeff_in4    (cfg_coeff4),
        .coeff_in5    (cfg_coeff5),
        .coeff_in6    (cfg_coeff6),
        .coeff_in7    (cfg_coeff7),
        .result_out   (fir_out),
        .result_valid (fir_valid)
    );

    // ----------------------------------------------------------------
    // Block 3: Threshold FSM with 3-sample Debounce
    // Fires single-cycle brake_irq after 3 consecutive sub-threshold
    // ----------------------------------------------------------------
    threshold_fsm u_fsm (
        .clk         (clk),
        .rst_n       (rst_n),
        .filtered_in (fir_out),
        .data_valid  (fir_valid),
        .threshold   (cfg_threshold),
        .brake_irq   (brake_irq)
    );

    // ----------------------------------------------------------------
    // Block 4: SPI Configuration Registers (with baud rate control)
    // Runtime-programmable threshold, filter coefficients, and baud rate
    // ----------------------------------------------------------------
    config_regs_gc #(
        .DEFAULT_THRESHOLD (16'd2560),
        .DEFAULT_COEFF0    (16'sd112),
        .DEFAULT_COEFF1    (16'sd243),
        .DEFAULT_COEFF2    (16'sd618),
        .DEFAULT_COEFF3    (16'sd1293),
        .DEFAULT_COEFF4    (16'sd2217),
        .DEFAULT_COEFF5    (16'sd3225),
        .DEFAULT_COEFF6    (16'sd4089),
        .DEFAULT_COEFF7    (16'sd4587),
        .DEFAULT_BAUD_DIV  (DEFAULT_BAUD_DIV)
    ) u_config (
        .clk       (clk),
        .rst_n     (rst_n),
        .spi_csn   (spi_csn),
        .spi_sck   (spi_sck),
        .spi_mosi  (spi_mosi),
        .threshold (cfg_threshold),
        .coeff0    (cfg_coeff0),
        .coeff1    (cfg_coeff1),
        .coeff2    (cfg_coeff2),
        .coeff3    (cfg_coeff3),
        .coeff4    (cfg_coeff4),
        .coeff5    (cfg_coeff5),
        .coeff6    (cfg_coeff6),
        .coeff7    (cfg_coeff7),
        .baud_div  (baud_div_w)
    );

endmodule