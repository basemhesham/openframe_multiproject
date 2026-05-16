//==============================================================================
// Module: nc_sync
// Description: Multi-stage Synchronizer for Clock Domain Crossing
//
// Copyright (c) 2020 nativechips.ai
// Author: Mohamed Shalan (shalan@nativechips.ai)
// License: Apache License 2.0
//
// Parameters:
//   NUM_STAGES - Number of synchronization stages (default: 2)
//==============================================================================

`timescale 1ns/1ps
`default_nettype none

module nc_sync #(parameter NUM_STAGES = 2) (
    input   wire    clk,
    input   wire    rst_n,
    input   wire    in,
    output  wire    out
);

    reg [NUM_STAGES-1:0] sync;

    always @(posedge clk or negedge rst_n)
        if (!rst_n)
            sync <= {NUM_STAGES{1'b0}};
        else
            sync <= {sync[NUM_STAGES-2:0], in};

    assign out = sync[NUM_STAGES-1];

endmodule

`default_nettype wire
