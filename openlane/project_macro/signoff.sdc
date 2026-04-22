#=============================================================
# project_macro — Signoff Constraints
#
# Applies at: OpenROAD.STAPostPNR (after SPEF extraction)
#
# I/O delays are identical to pnr.sdc because both the OpenFrame
# wrapper SDC and the internal infrastructure measurements use
# the same external delay value (4 ns) in both files.
#
# What changes vs. pnr.sdc:
#   - clock_uncertainty  0.10 ns  (pnr: 0.15 ns)
#   - timing_derate      ±5 %     (pnr: ±7 %)
#   - max_transition     1.50 ns  (pnr: 0.75 ns)
#
# HOW TO USE: replace only the two <<...>> clock latency
# placeholders with your values from Section 5.1.
#=============================================================

set clk_port clk

create_clock [get_ports $clk_port] \
    -name clk \
    -period $::env(CLOCK_PERIOD)

set_propagated_clock [get_clocks {clk}]

# ── Clock non-idealities (signoff — relaxed) ──────────────
set_clock_uncertainty 0.10 [get_clocks {clk}]
set_max_transition    1.50 [current_design]
set_max_fanout        16   [current_design]

set_timing_derate -early [expr {1 - 0.05}]
set_timing_derate -late  [expr {1 + 0.05}]

# ── Clock source latency ──────────────────────────────────
# Identical to pnr.sdc — physical measurement, not estimate.
#
# *** REPLACE WITH YOUR VALUES FROM SECTION 5.1 ***
set_clock_latency -source -max 10.305 [get_clocks {clk}]
set_clock_latency -source -min 6.200 [get_clocks {clk}]

set_input_transition 0.80 [get_ports $clk_port]

# ── Reset and POR ─────────────────────────────────────────
set_input_delay [expr {$::env(CLOCK_PERIOD) * 0.5}] \
    -clock [get_clocks {clk}] [get_ports {reset_n por_n}]

# ── GPIO input delays ─────────────────────────────────────
# Same values as pnr.sdc. The wrapper SDC uses ext_delay = 4
# in both PnR and signoff, so these constraints do not change.
#
# Bottom edge (gpio_bot_in) → Right Purple + Bottom Orange
set_input_delay -max 15.12 \
    -clock [get_clocks {clk}] [get_ports {gpio_bot_in[*]}]
set_input_delay -min 7.08 \
    -clock [get_clocks {clk}] [get_ports {gpio_bot_in[*]}]

# Right edge (gpio_rt_in) → Top Purple + Right Orange
set_input_delay -max 15.05 \
    -clock [get_clocks {clk}] [get_ports {gpio_rt_in[*]}]
set_input_delay -min 7.20 \
    -clock [get_clocks {clk}] [get_ports {gpio_rt_in[*]}]

# Top edge (gpio_top_in) → Left Purple + Top Orange
set_input_delay -max 14.25 \
    -clock [get_clocks {clk}] [get_ports {gpio_top_in[*]}]
set_input_delay -min 6.22 \
    -clock [get_clocks {clk}] [get_ports {gpio_top_in[*]}]

set_input_transition -max 0.38 [get_ports {gpio_bot_in[*]}]
set_input_transition -min 0.05 [get_ports {gpio_bot_in[*]}]
set_input_transition -max 0.38 [get_ports {gpio_rt_in[*]}]
set_input_transition -min 0.05 [get_ports {gpio_rt_in[*]}]
set_input_transition -max 0.38 [get_ports {gpio_top_in[*]}]
set_input_transition -min 0.05 [get_ports {gpio_top_in[*]}]

# ── GPIO output delays ────────────────────────────────────
# Same values as pnr.sdc for the same reason.
set_output_delay -max 22.73 \
    -clock [get_clocks {clk}] \
    [get_ports {gpio_bot_out[*] gpio_rt_out[*] gpio_top_out[*]}]
set_output_delay -min 10.82 \
    -clock [get_clocks {clk}] \
    [get_ports {gpio_bot_out[*] gpio_rt_out[*] gpio_top_out[*]}]

set_output_delay -max 23.13 \
    -clock [get_clocks {clk}] \
    [get_ports {gpio_bot_oeb[*] gpio_rt_oeb[*] gpio_top_oeb[*]}]
set_output_delay -min 9.26 \
    -clock [get_clocks {clk}] \
    [get_ports {gpio_bot_oeb[*] gpio_rt_oeb[*] gpio_top_oeb[*]}]

set_output_delay -max 22.73 \
    -clock [get_clocks {clk}] \
    [get_ports {gpio_bot_dm[*] gpio_rt_dm[*] gpio_top_dm[*]}]
set_output_delay -min 10.82 \
    -clock [get_clocks {clk}] \
    [get_ports {gpio_bot_dm[*] gpio_rt_dm[*] gpio_top_dm[*]}]

set_load 0.19 [all_outputs]
