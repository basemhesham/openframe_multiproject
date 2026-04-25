#===========================================================================#
# OPENFRAME SIGNOFF CONSTRAINTS
#===========================================================================#

#---------------------------------------------------------------------------#
# 1. ENVIRONMENT & TIMING VARIABLES
#---------------------------------------------------------------------------#
set CLK_PERIOD_SYS   50
set CLK_PERIOD_SCAN  100
set IN_DELAY_VAL     4
set OUT_DELAY_VAL    20
set DERATE_FACTOR    0.05
set MIN_CAP          0.04
set MAX_CAP          0.04
set MIN_TRAN         1.0
set MAX_TRAN         1.19
set MAX_TRANS_LIMIT  1.5
set MAX_FANOUT_VAL   20

#---------------------------------------------------------------------------#
# 2. CLOCK DEFINITIONS
#---------------------------------------------------------------------------#
# System Clock
create_clock -name sys_clk  -period $CLK_PERIOD_SYS  [get_ports {gpio_in[38]}]

# Scan Clock
create_clock -name scan_clk -period $CLK_PERIOD_SCAN [get_ports {gpio_in[40]}]

set_propagated_clock [all_clocks]

# Clock Groups (Logically Exclusive)
set_clock_groups \
   -name clock_group \
   -logically_exclusive \
   -group [get_clocks {sys_clk}] \
   -group [get_clocks {scan_clk}]

#---------------------------------------------------------------------------#
# 3. DESIGN LIMITS & NON-IDEALITIES
#---------------------------------------------------------------------------#
set_clock_uncertainty 0.1 [all_clocks]
set_max_transition    $MAX_TRANS_LIMIT [current_design]
set_max_fanout        $MAX_FANOUT_VAL  [current_design]

# Timing Derates (PVT Variation)
puts "Setting derate factor to: [expr $DERATE_FACTOR * 100] %"
set_timing_derate -early [expr 1 - $DERATE_FACTOR]
set_timing_derate -late  [expr 1 + $DERATE_FACTOR]

#---------------------------------------------------------------------------#
# 4. INPUT/OUTPUT DELAYS
#---------------------------------------------------------------------------#
puts "Setting input delay to: $IN_DELAY_VAL"
puts "Setting output delay to: $OUT_DELAY_VAL"

# General I/O Delays (Referenced to sys_clk)
set_input_delay  $IN_DELAY_VAL  -clock [get_clocks {sys_clk}] -add_delay [all_inputs]
set_output_delay $OUT_DELAY_VAL -clock [get_clocks {sys_clk}] -add_delay [all_outputs]

# Clock Ports - Zero Delay
set_input_delay 0 -clock [get_clocks {sys_clk}]  [get_ports {gpio_in[38]}]
set_input_delay 0 -clock [get_clocks {scan_clk}] [get_ports {gpio_in[40]}]

#---------------------------------------------------------------------------#
# 5. ELECTRICAL CONSTRAINTS (Loads & Transitions)
#---------------------------------------------------------------------------#
puts "Cap load range: $MIN_CAP : $MAX_CAP"
set_load -min $MIN_CAP [all_outputs]
set_load -max $MAX_CAP [all_outputs]

puts "Input transition range: $MIN_TRAN : $MAX_TRAN"
set_input_transition -min $MIN_TRAN [all_inputs]
set_input_transition -max $MAX_TRAN [all_inputs]

#---------------------------------------------------------------------------#
# 6. TIMING EXCEPTIONS (False Paths)
#---------------------------------------------------------------------------#
set_false_path -from [get_ports {por*}]
set_false_path -from [get_ports {resetb*}]

