// =========================================================
// Module: config_regs_gc
// Purpose: SPI configuration registers with runtime baud rate control
// Derived from: config_regs.sv
// Change from parent: Added baud_div register at address 0x09
// =========================================================

module config_regs_gc #(
    parameter logic [15:0] DEFAULT_THRESHOLD = 16'd2560,
    parameter logic [15:0] DEFAULT_COEFF0    = 16'sd112,
    parameter logic [15:0] DEFAULT_COEFF1    = 16'sd243,
    parameter logic [15:0] DEFAULT_COEFF2    = 16'sd618,
    parameter logic [15:0] DEFAULT_COEFF3    = 16'sd1293,
    parameter logic [15:0] DEFAULT_COEFF4    = 16'sd2217,
    parameter logic [15:0] DEFAULT_COEFF5    = 16'sd3225,
    parameter logic [15:0] DEFAULT_COEFF6    = 16'sd4089,
    parameter logic [15:0] DEFAULT_COEFF7    = 16'sd4587,
    parameter logic [15:0] DEFAULT_BAUD_DIV  = 16'd108
) (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        spi_csn,
    input  logic        spi_sck,
    input  logic        spi_mosi,

    output logic [15:0] threshold,
    output logic [15:0] coeff0,
    output logic [15:0] coeff1,
    output logic [15:0] coeff2,
    output logic [15:0] coeff3,
    output logic [15:0] coeff4,
    output logic [15:0] coeff5,
    output logic [15:0] coeff6,
    output logic [15:0] coeff7,
    output logic [15:0] baud_div
);

    localparam int unsigned FRAME_BITS  = 24;
    localparam int unsigned ADDR_MSB    = 23;
    localparam int unsigned ADDR_LSB    = 16;
    localparam int unsigned DATA_MSB    = 15;
    localparam int unsigned DATA_LSB    = 0;
    localparam int unsigned BIT_CNT_W   = $clog2(FRAME_BITS);

    localparam logic [7:0] REG_THRESHOLD = 8'h00;
    localparam logic [7:0] REG_COEFF0    = 8'h01;
    localparam logic [7:0] REG_COEFF1    = 8'h02;
    localparam logic [7:0] REG_COEFF2    = 8'h03;
    localparam logic [7:0] REG_COEFF3    = 8'h04;
    localparam logic [7:0] REG_COEFF4    = 8'h05;
    localparam logic [7:0] REG_COEFF5    = 8'h06;
    localparam logic [7:0] REG_COEFF6    = 8'h07;
    localparam logic [7:0] REG_COEFF7    = 8'h08;
    localparam logic [7:0] REG_BAUD_DIV  = 8'h09;

    logic                  sck_meta_q;
    logic                  sck_sync_q;
    logic                  sck_sync_d_q;
    logic                  csn_meta_q;
    logic                  csn_sync_q;
    logic                  mosi_meta_q;
    logic                  mosi_sync_q;
    logic [FRAME_BITS-1:0] shift_q;
    logic [FRAME_BITS-1:0] frame_next;
    logic [BIT_CNT_W-1:0]  bit_cnt_q;
    logic                  sck_rise;

    assign sck_rise   = sck_sync_q && !sck_sync_d_q;
    assign frame_next = {shift_q[FRAME_BITS-2:0], mosi_sync_q};

    // Bring the external SPI pins into the 25 MHz system clock domain.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sck_meta_q   <= 1'b0;
            sck_sync_q   <= 1'b0;
            sck_sync_d_q <= 1'b0;
            csn_meta_q   <= 1'b1;
            csn_sync_q   <= 1'b1;
            mosi_meta_q  <= 1'b0;
            mosi_sync_q  <= 1'b0;
        end else begin
            sck_meta_q   <= spi_sck;
            sck_sync_q   <= sck_meta_q;
            sck_sync_d_q <= sck_sync_q;
            csn_meta_q   <= spi_csn;
            csn_sync_q   <= csn_meta_q;
            mosi_meta_q  <= spi_mosi;
            mosi_sync_q  <= mosi_meta_q;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            threshold <= DEFAULT_THRESHOLD;
            coeff0    <= DEFAULT_COEFF0;
            coeff1    <= DEFAULT_COEFF1;
            coeff2    <= DEFAULT_COEFF2;
            coeff3    <= DEFAULT_COEFF3;
            coeff4    <= DEFAULT_COEFF4;
            coeff5    <= DEFAULT_COEFF5;
            coeff6    <= DEFAULT_COEFF6;
            coeff7    <= DEFAULT_COEFF7;
            baud_div  <= DEFAULT_BAUD_DIV;
            shift_q   <= '0;
            bit_cnt_q <= '0;
        end else begin
            if (csn_sync_q) begin
                shift_q   <= '0;
                bit_cnt_q <= '0;
            end else if (sck_rise) begin
                shift_q <= frame_next;

                if (bit_cnt_q == FRAME_BITS - 1) begin
                    bit_cnt_q <= '0;

                    unique case (frame_next[ADDR_MSB:ADDR_LSB])
                        REG_THRESHOLD: threshold <= frame_next[DATA_MSB:DATA_LSB];
                        REG_COEFF0:    coeff0    <= frame_next[DATA_MSB:DATA_LSB];
                        REG_COEFF1:    coeff1    <= frame_next[DATA_MSB:DATA_LSB];
                        REG_COEFF2:    coeff2    <= frame_next[DATA_MSB:DATA_LSB];
                        REG_COEFF3:    coeff3    <= frame_next[DATA_MSB:DATA_LSB];
                        REG_COEFF4:    coeff4    <= frame_next[DATA_MSB:DATA_LSB];
                        REG_COEFF5:    coeff5    <= frame_next[DATA_MSB:DATA_LSB];
                        REG_COEFF6:    coeff6    <= frame_next[DATA_MSB:DATA_LSB];
                        REG_COEFF7:    coeff7    <= frame_next[DATA_MSB:DATA_LSB];
                        REG_BAUD_DIV:  baud_div  <= frame_next[DATA_MSB:DATA_LSB];
                        default: begin
                            // Invalid write addresses are ignored.
                        end
                    endcase
                end else begin
                    bit_cnt_q <= bit_cnt_q + 1'b1;
                end
            end
        end
    end

endmodule
