// SPDX-License-Identifier: Apache-2.0
// OpenFrame Multi-Project Chip — Netlist Includes

`ifndef PnR
`ifdef SIM
`define USE_POWER_PINS
`endif
`endif
`define OPENFRAME_IO_PADS 44

`ifndef PnR
    `include "tech_lib/tech_buf.v"
    `include "tech_lib/tech_clkbuf.v"
    `include "tech_lib/tech_clkgate.v"
    `include "scan_macro_node.v"
    `include "green_macro.v"
    `include "orange_macro_v.v"
    `include "purple_macro_p3.v"
    `include "project_macro.v"
    `include "scan_controller_macro.v"
    `include "vccd1_connection.v"
    `include "vssd1_connection.v"
`endif
