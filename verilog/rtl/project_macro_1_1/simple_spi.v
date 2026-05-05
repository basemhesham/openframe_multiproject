`timescale 1ns/1ps
`default_nettype none

module simple_spi (
    input  wire        clk,
    input  wire        rst_n,
    
    // SPI Physical Pins
    input  wire        cs_n,
    input  wire        sclk,
    input  wire        mosi,
    output wire        miso,
    
    // Wrapper Interface
    output reg  [7:0]  addr,
    output reg  [63:0] din,
    input  wire [63:0] dout,
    output reg  [7:0]  data_we,
    output reg  [7:0]  weight_we,
    output reg         start,
    output reg  [15:0] data_len,
    output reg  [3:0]  col_mask,
    input  wire        busy,
    input  wire        done
);

    // Synchronize SPI signals to local clock
    reg [1:0] sclk_sync, cs_n_sync, mosi_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk_sync <= 2'b11;
            cs_n_sync <= 2'b11;
            mosi_sync <= 2'b00;
        end else begin
            sclk_sync <= {sclk_sync[0], sclk};
            cs_n_sync <= {cs_n_sync[0], cs_n};
            mosi_sync <= {mosi_sync[0], mosi};
        end
    end

    wire sclk_rise = (sclk_sync == 2'b01);
    wire sclk_fall = (sclk_sync == 2'b10);
    wire cs_n_active = ~cs_n_sync[0];

    reg [7:0] bit_cnt;
    reg [7:0] cmd;
    reg [127:0] shift_reg;
    reg [63:0] miso_shift;

    assign miso = miso_shift[63];

    // SPI Synchronous Logic (Single Edge)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt <= 8'h0;
            cmd <= 8'h0;
            shift_reg <= 128'b0;
            addr <= 8'h0;
            din <= 64'b0;
            data_we <= 8'h0;
            weight_we <= 8'h0;
            start <= 1'b0;
            data_len <= 16'd4;
            col_mask <= 4'hF;
            miso_shift <= 64'b0;
        end else if (cs_n_sync[0]) begin // High (Inactive)
            bit_cnt <= 8'h0;
            cmd <= 8'h0;
            data_we <= 8'h0;
            weight_we <= 8'h0;
            start <= 1'b0;
            miso_shift <= 64'b0;
        end else begin
            if (sclk_rise) begin
                shift_reg <= {shift_reg[126:0], mosi_sync[0]};
                bit_cnt <= bit_cnt + 8'd1;
                
                if (bit_cnt == 8'd7) begin
                    cmd <= {shift_reg[6:0], mosi_sync[0]};
                    if ({shift_reg[6:0], mosi_sync[0]} == 8'h04) start <= 1'b1;
                end

                // Data Write: Cmd(8) + Addr(8) + Data(64) = 80 bits
                if (cmd == 8'h01 && bit_cnt == 8'd79) begin
                    addr <= shift_reg[70:63];
                    din <= {shift_reg[62:0], mosi_sync[0]};
                    data_we <= 8'hFF;
                end
                
                // Weight Write: Cmd(8) + Addr(8) + Data(64) = 80 bits
                if (cmd == 8'h02 && bit_cnt == 8'd79) begin
                    addr <= shift_reg[70:63];
                    din <= {shift_reg[62:0], mosi_sync[0]};
                    weight_we <= 8'hFF;
                end

                // Read: Cmd(8) + Addr(8) = 16 bits.
                if (cmd == 8'h03 && bit_cnt == 8'd15) begin
                    addr <= {shift_reg[6:0], mosi_sync[0]};
                end
                
                // Start: Cmd(8)
                if (cmd == 8'h04 && bit_cnt == 8'd7) begin
                    start <= 1'b1;
                end
            end

            if (sclk_fall) begin
                if (cmd == 8'h03 && bit_cnt == 8'd16) begin
                    miso_shift <= dout;
                end else if (cmd == 8'h05 && bit_cnt == 8'd8) begin
                    miso_shift <= {busy, done, 62'b0};
                end else begin
                    miso_shift <= {miso_shift[62:0], 1'b0};
                end
            end

            // Auto-clear pulses
            if (data_we != 0) data_we <= 8'h0;
            if (weight_we != 0) weight_we <= 8'h0;
            if (start) start <= 1'b0;
        end
    end

endmodule
