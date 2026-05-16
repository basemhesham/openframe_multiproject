// SPDX-License-Identifier: Apache-2.0
//
// Black-box stubs for project-level synthesis.
//
// Each module here is a HARD MACRO that arrives at floor-plan time as a
// LEF/LIB pair. Logic synthesis must NOT see the implementation — only
// the port list — so Yosys preserves the instance and routing tools
// place the macro abutted into the floorplan.
//
// (* blackbox *) tells Yosys to keep the cell as an opaque instance and
// (* keep_hierarchy *) prevents `flatten` from unrolling it.

(* blackbox *) (* keep_hierarchy *)
module sky130_ef_ip__rc_osc_16M (ena, dout);
    input  ena;
    output dout;
endmodule

(* blackbox *) (* keep_hierarchy *)
module sky130_ef_ip__rc_osc_500k (ena, dout);
    input  ena;
    output dout;
endmodule

// All-digital PoR macro — hardened separately under por_macro/.
(* blackbox *) (* keep_hierarchy *)
module por_macro (por_n_out);
    output por_n_out;
endmodule

// Fractional-N DLL (FLL) — hard macro from fracn_dll (Efabless / RTE).
// Mixed-signal: ring oscillator + analog-ish trim controller.
(* blackbox *) (* keep_hierarchy *)
module dll (resetb, enable, osc, clockp, div, dco, ext_trim);
    input        resetb;
    input        enable;
    input        osc;
    input  [7:0] div;
    input        dco;
    input [25:0] ext_trim;
    output [1:0] clockp;
endmodule

