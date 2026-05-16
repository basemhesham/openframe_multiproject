//==============================================================================
// Module: nc_fifo
// Description: Parameterized Synchronous FIFO
//
// Copyright (c) 2020 nativechips.ai
// Author: Mohamed Shalan (shalan@nativechips.ai)
// License: Apache License 2.0
//
// Parameters:
//   DW - Data width (default: 8)
//   AW - Address width, depth = 2^AW (default: 4)
//==============================================================================

`timescale 1ns/1ps
`default_nettype none

module nc_fifo #(parameter DW=8, AW=4)(
    input   wire            clk,
    input   wire            rst_n,
    input   wire            rd,
    input   wire            wr,
    input   wire            flush,
    input   wire [DW-1:0]   wdata,
    output  wire            empty,
    output  wire            full,
    output  wire [DW-1:0]   rdata,
    output  wire [AW:0]     level    // AW+1 bits to represent 0 to 2^AW entries
);

    localparam  DEPTH = 2**AW;

    //Internal Signal declarations
    reg [DW-1:0]  array_reg [DEPTH-1:0];
    reg [AW-1:0]  w_ptr_reg;
    reg [AW-1:0]  w_ptr_next;
    wire [AW-1:0] w_ptr_succ;
    reg [AW-1:0]  r_ptr_reg;
    reg [AW-1:0]  r_ptr_next;
    wire [AW-1:0] r_ptr_succ;

    // Level
    reg [AW:0] level_reg;    // AW+1 bits to represent 0 to 2^AW entries
    reg [AW:0] level_next;
    reg full_reg;
    reg empty_reg;
    reg full_next;
    reg empty_next;

    wire w_en;
    wire r_en;

    // Body
    assign w_en = wr & ~full_reg;
    assign r_en = rd & ~empty_reg;

    // Output logic
    assign rdata = array_reg[r_ptr_reg];
    assign empty = empty_reg;
    assign full  = full_reg;
    assign level = level_reg;

    // Registers
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_ptr_reg <= {AW{1'b0}};
            r_ptr_reg <= {AW{1'b0}};
            full_reg  <= 1'b0;
            empty_reg <= 1'b1;
            level_reg <= {AW+1{1'b0}};
        end else if (flush) begin
            w_ptr_reg <= {AW{1'b0}};
            r_ptr_reg <= {AW{1'b0}};
            full_reg  <= 1'b0;
            empty_reg <= 1'b1;
            level_reg <= {AW+1{1'b0}};
        end else begin
            w_ptr_reg <= w_ptr_next;
            r_ptr_reg <= r_ptr_next;
            full_reg  <= full_next;
            empty_reg <= empty_next;
            level_reg <= level_next;
        end
    end

    // Next state logic
    always @* begin
        w_ptr_next = w_ptr_reg;
        r_ptr_next = r_ptr_reg;
        full_next  = full_reg;
        empty_next = empty_reg;
        level_next = level_reg;

        case ({w_en, r_en})
            2'b10: begin
                // Write-only
                w_ptr_next = w_ptr_succ;
                level_next = level_reg + 1'b1;
                full_next  = (level_reg == DEPTH - 1);
                empty_next = 1'b0;
            end

            2'b01: begin
                // Read-only
                r_ptr_next = r_ptr_succ;
                level_next = level_reg - 1'b1;
                full_next  = 1'b0;
                empty_next = (level_reg == 1);
            end

            2'b11: begin
                // Simultaneous read/write keeps occupancy unchanged.
                // Preserve empty/full flags to avoid false-empty/full at boundary levels.
                w_ptr_next = w_ptr_succ;
                r_ptr_next = r_ptr_succ;
                level_next = level_reg;
                full_next  = full_reg;
                empty_next = empty_reg;
            end

            default: begin
                // No operation
            end
        endcase
    end

    // Successor pointers
    assign w_ptr_succ = w_ptr_reg + 1'b1;
    assign r_ptr_succ = r_ptr_reg + 1'b1;

    // Memory write
    integer i;
    always @(posedge clk) begin
        if (w_en)
            array_reg[w_ptr_reg] <= wdata;
    end

endmodule

`default_nettype wire
