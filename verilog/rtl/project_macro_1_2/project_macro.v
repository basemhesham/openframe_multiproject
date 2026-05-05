// SPDX-License-Identifier: Apache-2.0
// project_macro — BLAKE2s (single-block) via 4-wire SPI interface
//
// Register-file back-end (blake2s_regs) ports:
//   clk, reset_n, cs, we, address[7:0], write_data[31:0], read_data[31:0]
//
// SPI protocol (MSB-first, 42-bit frame, CPOL=0 CPHA=0):
//   Bit[41]   : R/nW  (1=read, 0=write)
//   Bit[40:33]: address[7:0]
//   Bit[32:1] : write_data[31:0] (ignored on reads)
//   Bit[0]    : padding
//
//   On a read, MISO shifts out read_data[31:0] MSB-first starting one
//   clock after the address has been decoded (bit 9 of the frame).
//
// GPIO assignment:
//   gpio_bot_in[0]  = spi_sclk    (from host)
//   gpio_bot_in[1]  = spi_cs_n    (from host, active low)
//   gpio_bot_in[2]  = spi_mosi    (from host)
//   gpio_bot_out[0] = spi_miso    (to host)
//   gpio_bot_out[14:1] = 14'b0    (unused, driven low)
//   All right and top GPIOs: unused inputs

`default_nettype none

module project_macro (
`ifdef USE_POWER_PINS
    inout vccd1,
    inout vssd1,
`endif
    input  wire        clk,
    input  wire        reset_n,
    input  wire        por_n,
    input  wire [14:0] gpio_bot_in,
    output wire [14:0] gpio_bot_out,
    output wire [14:0] gpio_bot_oeb,
    output wire [44:0] gpio_bot_dm,
    input  wire [8:0]  gpio_rt_in,
    output wire [8:0]  gpio_rt_out,
    output wire [8:0]  gpio_rt_oeb,
    output wire [26:0] gpio_rt_dm,
    input  wire [13:0] gpio_top_in,
    output wire [13:0] gpio_top_out,
    output wire [13:0] gpio_top_oeb,
    output wire [41:0] gpio_top_dm
);

    // ----------------------------------------------------------------
    // SPI signal extraction
    // ----------------------------------------------------------------
    wire spi_sclk = gpio_bot_in[0];
    wire spi_cs_n = gpio_bot_in[1];
    wire spi_mosi = gpio_bot_in[2];

    // ----------------------------------------------------------------
    // SPI-to-register-file bridge
    // ----------------------------------------------------------------
    reg  [5:0]  bit_cnt;
    reg  [41:0] shift_in;
    reg  [31:0] shift_out;
    reg          spi_sclk_r;

    // Register-file drive signals (same timing as workshop AES template)
    reg          bus_cs;
    reg          bus_we;
    reg  [7:0]   bus_addr;
    reg  [31:0]  bus_wdata;

    wire [31:0]  bus_rdata;

    wire sclk_posedge = spi_sclk  & ~spi_sclk_r;
    wire sclk_negedge = ~spi_sclk &  spi_sclk_r;
    wire shift_out_load = (bit_cnt == 6'd9) & shift_in[8];
    wire [3:0] shift_out_load_buf;
    wire [41:0] shift_in_sampled = {shift_in[40:0], spi_mosi};

`ifdef SCL_sky130_fd_sc_hd
    /* verilator lint_off PINMISSING */
    sky130_fd_sc_hd__buf_4 shift_out_load_buf_0 (.A(shift_out_load), .X(shift_out_load_buf[0]));
    sky130_fd_sc_hd__buf_4 shift_out_load_buf_1 (.A(shift_out_load), .X(shift_out_load_buf[1]));
    sky130_fd_sc_hd__buf_4 shift_out_load_buf_2 (.A(shift_out_load), .X(shift_out_load_buf[2]));
    sky130_fd_sc_hd__buf_4 shift_out_load_buf_3 (.A(shift_out_load), .X(shift_out_load_buf[3]));
    /* verilator lint_on PINMISSING */
`else
    assign shift_out_load_buf = {4{shift_out_load}};
`endif

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            bit_cnt    <= 6'd0;
            shift_in   <= 42'd0;
            shift_out  <= 32'd0;
            spi_sclk_r <= 1'b0;
            bus_cs     <= 1'b0;
            bus_we     <= 1'b0;
            bus_addr   <= 8'd0;
            bus_wdata  <= 32'd0;
        end else begin
            spi_sclk_r <= spi_sclk;
            bus_cs     <= 1'b0;
            bus_we     <= 1'b0;

            if (spi_cs_n) begin
                // Deselected — reset frame state
                bit_cnt  <= 6'd0;
                shift_in <= 42'd0;
            end else begin
                // ---- Sample MOSI on rising SCLK ----
                if (sclk_posedge) begin
                    shift_in <= shift_in_sampled;
                    bit_cnt  <= bit_cnt + 6'd1;

                    // After 9 clocks the R/nW + address are available.
                    // Immediately issue the register read cycle so read_data
                    // is ready to load into shift_out on the next negedge.
                    if (bit_cnt == 6'd8) begin
                        if (shift_in_sampled[8]) begin  // R/nW = 1 → read
                            bus_cs   <= 1'b1;
                            bus_we   <= 1'b0;
                            bus_addr <= shift_in_sampled[7:0];
                        end
                    end

                    // Full 42-bit frame received
                    if (bit_cnt == 6'd41) begin
                        if (!shift_in_sampled[41]) begin // R/nW = 0 → write
                            bus_cs    <= 1'b1;
                            bus_we    <= 1'b1;
                            bus_addr  <= shift_in_sampled[40:33];
                            bus_wdata <= shift_in_sampled[32:1];
                        end
                        bit_cnt  <= 6'd0;
                        shift_in <= 42'd0;
                    end
                end

                // ---- Shift MISO out on falling SCLK ----
                if (sclk_negedge) begin
                    // Split the load control so the shift_out mux select does
                    // not become a single high-fanout antenna hotspot.
                    if (shift_out_load_buf[0]) begin
                        shift_out[7:0] <= bus_rdata[7:0];
                    end else begin
                        shift_out[7:0] <= {shift_out[6:0], 1'b0};
                    end

                    if (shift_out_load_buf[1]) begin
                        shift_out[15:8] <= bus_rdata[15:8];
                    end else begin
                        shift_out[15:8] <= shift_out[14:7];
                    end

                    if (shift_out_load_buf[2]) begin
                        shift_out[23:16] <= bus_rdata[23:16];
                    end else begin
                        shift_out[23:16] <= shift_out[22:15];
                    end

                    if (shift_out_load_buf[3]) begin
                        shift_out[31:24] <= bus_rdata[31:24];
                    end else begin
                        shift_out[31:24] <= shift_out[30:23];
                    end
                end
            end
        end
    end

    // ----------------------------------------------------------------
    // BLAKE2s register wrapper
    // ----------------------------------------------------------------
    blake2s_regs u_blake2s (
        .clk        (clk),
        .reset_n    (reset_n),
        .cs         (bus_cs),
        .we         (bus_we),
        .address    (bus_addr),
        .write_data (bus_wdata),
        .read_data  (bus_rdata)
    );

    // ----------------------------------------------------------------
    // GPIO output assignments
    // gpio_bot_out[0] = MISO (output)
    // gpio_bot_out[14:1] = low (unused)
    // ----------------------------------------------------------------
    assign gpio_bot_out    = {14'b0, shift_out[31]};
    assign gpio_bot_oeb    = {14'h3FFF, 1'b0};   // [0]=output, [14:1]=input

    // Right and top: all safe inputs, driven low
    assign gpio_rt_out     = 9'b0;
    assign gpio_rt_oeb     = {9{1'b1}};
    assign gpio_top_out    = 14'b0;
    assign gpio_top_oeb    = {14{1'b1}};

    // Drive modes — strong push-pull for all pads
    genvar i;
    generate
        for (i = 0; i < 15; i = i + 1) begin : gen_bot_dm
            assign gpio_bot_dm[i*3 +: 3] = 3'b110;
        end
        for (i = 0; i < 9; i = i + 1) begin : gen_rt_dm
            assign gpio_rt_dm[i*3 +: 3] = 3'b110;
        end
        for (i = 0; i < 14; i = i + 1) begin : gen_top_dm
            assign gpio_top_dm[i*3 +: 3] = 3'b110;
        end
    endgenerate

endmodule
