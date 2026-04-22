#=============================================================
# project_macro — PnR Constraints
#
# Applies during: Synthesis → Placement → CTS → Routing
#
# All I/O delays account for two layers:
#   1. OpenFrame wrapper external boundary (board + pad delays
#      from the wrapper-level SDC, ext_delay = 4 ns)
#   2. Internal infrastructure (purple + orange macros, measured
#      from wrapper-level post-PnR STA)
#
# HOW TO USE THIS FILE:
#   1. Find your grid position in the wrapper config.json
#      (e.g. gen_row[2].gen_col[1].u_proj = Row 2, Col 1)
#   2. Look up your clock latency in Section 5.1 of the guide.
#   3. Replace the two <<...>> placeholders below.
#   4. Leave everything else unchanged.
#=============================================================

set clk_port clk

create_clock [get_ports $clk_port] \
    -name clk \
    -period $::env(CLOCK_PERIOD)

set_propagated_clock [get_clocks {clk}]

# ── Clock non-idealities (PnR — pessimistic) ──────────────
set_clock_uncertainty 0.15 [get_clocks {clk}]
set_max_transition    0.75 [current_design]
set_max_fanout        16   [current_design]

set_timing_derate -early [expr {1 - 0.07}]
set_timing_derate -late  [expr {1 + 0.07}]

# ── Clock source latency ──────────────────────────────────
# Measured propagation from the external clock source to your
# macro's clk port. Includes: board + Caravel pad buffer +
# green column chain + ICG cell.
#
# *** REPLACE WITH YOUR VALUES FROM SECTION 5.1 ***
set_clock_latency -source -max 10.305 [get_clocks {clk}]
set_clock_latency -source -min 6.200 [get_clocks {clk}]

set_input_transition 0.80 [get_ports $clk_port]

# ── Reset and POR ─────────────────────────────────────────
set_input_delay [expr {$::env(CLOCK_PERIOD) * 0.5}] \
    -clock [get_clocks {clk}] [get_ports {reset_n por_n}]

# ── GPIO input delays ─────────────────────────────────────
# Total path: external board (4 ns) + Caravel pad buffer
# (4.55/1.26 ns) + purple broadcast buffer + orange local
# buffer → YOUR gpio_*_in port.
# Values differ per edge (different purple macro distance).
# They are the same for all 12 project locations.
#
# Bottom edge (gpio_bot_in) → via Right Purple + Bottom Orange
#   max = 8.55 + 6.57 = 15.12 ns  (slow corner)
#   min = 5.26 + 1.82 =  7.08 ns  (fast corner)
set_input_delay -max 15.12 \
    -clock [get_clocks {clk}] [get_ports {gpio_bot_in[*]}]
set_input_delay -min 7.08 \
    -clock [get_clocks {clk}] [get_ports {gpio_bot_in[*]}]

# Right edge (gpio_rt_in) → via Top Purple + Right Orange
#   max = 8.55 + 6.50 = 15.05 ns
#   min = 5.26 + 1.94 =  7.20 ns
set_input_delay -max 15.05 \
    -clock [get_clocks {clk}] [get_ports {gpio_rt_in[*]}]
set_input_delay -min 7.20 \
    -clock [get_clocks {clk}] [get_ports {gpio_rt_in[*]}]

# Top edge (gpio_top_in) → via Left Purple + Top Orange
#   max = 8.55 + 5.70 = 14.25 ns
#   min = 5.26 + 0.96 =  6.22 ns
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
# Total path: YOUR gpio_*_out → orange sel-gate + orange MUX
# chain (9.61 ns) + purple mux → OpenFrame gpio_out port →
# external board (4 ns) + receiving device setup (9.12 ns).
# The same for all 12 project locations and all three edges.
#
#   gpio_*_out: max = 9.61 + 13.12 = 22.73 ns
#               min = 2.92 +  7.90 = 10.82 ns
#   gpio_*_oeb: max = 9.81 + 13.32 = 23.13 ns  (+0.2 ns margin)
#               min = 2.92 +  6.34 =  9.26 ns
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
