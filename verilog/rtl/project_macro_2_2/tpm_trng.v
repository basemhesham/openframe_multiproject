// =============================================================================
// tpm_trng.v — True Random Number Generator
// =============================================================================
// Three independent ring-oscillator cells. Each cell is an odd chain of
// inverters connected in feedback. On real silicon the oscillation frequency
// drifts due to thermal noise — this jitter is the physical entropy source.
//
// (* keep *) stops Yosys from removing the combinational feedback loops.
// Verify in the post-synthesis netlist that all three rings survived.
//
// Simulation note: ring oscillator loops evaluate to X in RTL simulation.
//   Compile with +define+SIMULATION to use $random-based byte generation.
//
// Output: one random byte every ~DECIM clock cycles after enable.
// =============================================================================
`timescale 1ns/1ps

module tpm_trng #(parameter DECIM = 16)(
    input  wire       clk,
    input  wire       rstn,
    input  wire       enable,
    output reg  [7:0] data,
    output reg        valid
);

`ifdef SIMULATION
// ---------------------------------------------------------------------------
// Simulation model: generate a fresh $random byte every DECIM clocks.
// Ring oscillator combinational loops are X in simulation (no initial state).
// ---------------------------------------------------------------------------
reg [$clog2(DECIM)-1:0] sim_cnt;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        sim_cnt <= 0;
        data    <= 8'hA5;
        valid   <= 0;
    end else begin
        valid <= 0;
        if (enable) begin
            if (sim_cnt == DECIM - 1) begin
                sim_cnt <= 0;
                data    <= $random;
                valid   <= 1;
            end else begin
                sim_cnt <= sim_cnt + 1;
            end
        end else begin
            sim_cnt <= 0;
        end
    end
end

`else
// ---------------------------------------------------------------------------
// Ring oscillators (3 cells, different lengths → different frequencies)
// ---------------------------------------------------------------------------
(* keep = "true" *) wire [4:0] ro0;   // 5-inverter ring
(* keep = "true" *) wire [6:0] ro1;   // 7-inverter ring
(* keep = "true" *) wire [8:0] ro2;   // 9-inverter ring

// Ring 0
sky130_fd_sc_hd__inv_1 r0_inv0 (.A(ro0[4]), .Y(ro0[0]));
sky130_fd_sc_hd__inv_1 r0_inv1 (.A(ro0[0]), .Y(ro0[1]));
sky130_fd_sc_hd__inv_1 r0_inv2 (.A(ro0[1]), .Y(ro0[2]));
sky130_fd_sc_hd__inv_1 r0_inv3 (.A(ro0[2]), .Y(ro0[3]));
sky130_fd_sc_hd__inv_1 r0_inv4 (.A(ro0[3]), .Y(ro0[4]));

// Ring 1
sky130_fd_sc_hd__inv_1 r1_inv0 (.A(ro1[6]), .Y(ro1[0]));
sky130_fd_sc_hd__inv_1 r1_inv1 (.A(ro1[0]), .Y(ro1[1]));
sky130_fd_sc_hd__inv_1 r1_inv2 (.A(ro1[1]), .Y(ro1[2]));
sky130_fd_sc_hd__inv_1 r1_inv3 (.A(ro1[2]), .Y(ro1[3]));
sky130_fd_sc_hd__inv_1 r1_inv4 (.A(ro1[3]), .Y(ro1[4]));
sky130_fd_sc_hd__inv_1 r1_inv5 (.A(ro1[4]), .Y(ro1[5]));
sky130_fd_sc_hd__inv_1 r1_inv6 (.A(ro1[5]), .Y(ro1[6]));

// Ring 2
sky130_fd_sc_hd__inv_1 r2_inv0 (.A(ro2[8]), .Y(ro2[0]));
sky130_fd_sc_hd__inv_1 r2_inv1 (.A(ro2[0]), .Y(ro2[1]));
sky130_fd_sc_hd__inv_1 r2_inv2 (.A(ro2[1]), .Y(ro2[2]));
sky130_fd_sc_hd__inv_1 r2_inv3 (.A(ro2[2]), .Y(ro2[3]));
sky130_fd_sc_hd__inv_1 r2_inv4 (.A(ro2[3]), .Y(ro2[4]));
sky130_fd_sc_hd__inv_1 r2_inv5 (.A(ro2[4]), .Y(ro2[5]));
sky130_fd_sc_hd__inv_1 r2_inv6 (.A(ro2[5]), .Y(ro2[6]));
sky130_fd_sc_hd__inv_1 r2_inv7 (.A(ro2[6]), .Y(ro2[7]));
sky130_fd_sc_hd__inv_1 r2_inv8 (.A(ro2[7]), .Y(ro2[8]));

// XOR three oscillator outputs
wire raw = ro0[0] ^ ro1[0] ^ ro2[0];

// ---------------------------------------------------------------------------
// Decimation: sample raw every DECIM system clock cycles
// ---------------------------------------------------------------------------
reg [$clog2(DECIM)-1:0] dcnt;
reg                      pulse;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin dcnt <= 0; pulse <= 0; end
    else if (enable) begin
        pulse <= 0;
        if (dcnt == DECIM-1) begin dcnt <= 0; pulse <= 1; end
        else                      dcnt <= dcnt + 1;
    end else begin dcnt <= 0; pulse <= 0; end
end

// ---------------------------------------------------------------------------
// Von Neumann de-bias
// ---------------------------------------------------------------------------
reg vn_phase, vn_prev, vn_bit, vn_ok;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin vn_phase<=0; vn_prev<=0; vn_bit<=0; vn_ok<=0; end
    else begin
        vn_ok <= 0;
        if (pulse) begin
            if (!vn_phase) begin vn_prev <= raw; vn_phase <= 1; end
            else begin
                vn_phase <= 0;
                if (raw != vn_prev) begin vn_bit <= raw; vn_ok <= 1; end
            end
        end
    end
end

// ---------------------------------------------------------------------------
// 8-bit shift register
// ---------------------------------------------------------------------------
reg [7:0] sr;
reg [2:0] bcnt;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin sr<=0; bcnt<=0; data<=0; valid<=0; end
    else begin
        valid <= 0;
        if (vn_ok) begin
            sr   <= {sr[6:0], vn_bit};
            bcnt <= bcnt + 1;
            if (bcnt == 7) begin data <= {sr[6:0], vn_bit}; valid <= 1; end
        end
    end
end
`endif

endmodule
