#===========================================================================#
# OPENFRAME MACRO CONSTRAINTS
#===========================================================================#

#---------------------------------------------------------------------------#
# 1. ENVIRONMENT & VARIABLES
#---------------------------------------------------------------------------#
set CLK_PERIOD_SYS  50
set CLK_PERIOD_SCAN 100
set DERATE_FACTOR   0.07
set IN_DELAY_VAL    4
set OUT_DELAY_VAL   22
set MIN_CAP         0.5
set MAX_CAP         1.0
set MIN_TRAN        1.0
set MAX_TRAN        1.19

#---------------------------------------------------------------------------#
# 2. CLOCK DEFINITIONS
#---------------------------------------------------------------------------#
create_clock [get_ports {gpio_in[38]}] -name sys_clk  -period $CLK_PERIOD_SYS
create_clock [get_ports {gpio_in[40]}] -name scan_clk -period $CLK_PERIOD_SCAN

set_propagated_clock [all_clocks]

set_clock_groups \
    -name clock_group \
    -logically_exclusive \
    -group [get_clocks {sys_clk}] \
    -group [get_clocks {scan_clk}]

#---------------------------------------------------------------------------#
# 3. DESIGN LIMITS & NON-IDEALITIES
#---------------------------------------------------------------------------#
set_clock_uncertainty 0.8  [all_clocks]
set_max_transition    0.5  [current_design]
set_max_fanout        20   [current_design]

# Timing Derates (Accounting for PVT variations)
puts "Setting derate factor to: [expr $DERATE_FACTOR * 100] %"
set_timing_derate -early [expr 1 - $DERATE_FACTOR]
set_timing_derate -late  [expr 1 + $DERATE_FACTOR]

#---------------------------------------------------------------------------#
# 4. INPUT/OUTPUT DELAYS
#---------------------------------------------------------------------------#

set_input_delay  $IN_DELAY_VAL  -clock [get_clocks {sys_clk}] -add_delay [all_inputs]
set_output_delay $OUT_DELAY_VAL -clock [get_clocks {sys_clk}] -add_delay [all_outputs]


set_input_delay 0 -clock [get_clocks {sys_clk}]  [get_ports {gpio_in[38]}]
set_input_delay 0 -clock [get_clocks {scan_clk}] [get_ports {gpio_in[40]}]

#---------------------------------------------------------------------------#
# 5. INPUT TRANSITION & OUTPUT LOAD
#---------------------------------------------------------------------------#
puts "Input transition range: $MIN_TRAN : $MAX_TRAN"
set_input_transition -min $MIN_TRAN [all_inputs]
set_input_transition -max $MAX_TRAN [all_inputs]

puts "Cap load range: $MIN_CAP : $MAX_CAP"
set_load -min $MIN_CAP [all_outputs]
set_load -max $MAX_CAP [all_outputs]

#---------------------------------------------------------------------------#
# 6. TIMING EXCEPTIONS (False Paths)
#---------------------------------------------------------------------------#
set_false_path -from [get_ports {por*}]
set_false_path -from [get_ports {resetb*}]

