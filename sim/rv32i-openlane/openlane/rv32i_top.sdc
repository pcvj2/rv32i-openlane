# rv32i_top.sdc — Timing Constraints for OpenLane
# Target: 50 MHz (20 ns period)

set clk_period 20.0
set clk_name   clk

create_clock -name $clk_name -period $clk_period [get_ports $clk_name]

# Input delay: 30% of clock period
set input_delay [expr {$clk_period * 0.3}]
set_input_delay  $input_delay -clock $clk_name [all_inputs]
set_input_delay  0.0          -clock $clk_name [get_ports $clk_name]

# Output delay: 30% of clock period
set output_delay [expr {$clk_period * 0.3}]
set_output_delay $output_delay -clock $clk_name [all_outputs]

# Reset is async but constrain for STA
set_false_path -from [get_ports rst_n]
