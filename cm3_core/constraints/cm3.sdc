#
# Internal timing constraints for Cortex-M3
#

# Ignore timing on async resets
set_false_path -from [get_ports *RESET* ]

# Get clocks
set cm3_sys [get_property NAME [get_clocks -of [get_nets -hierarchical FCLK ]]]
set cm3_dbg [get_property NAME [get_clocks -of [get_nets -hierarchical SWCKTCK ]]]

# Set JTAG clock as asynchronous
set_clock_groups -asynchronous -group $cm3_dbg -group $cm3_sys

# Get JTAG Period
set jtag_period [get_property PERIOD [get_clocks -of [get_nets -hierarchical SWCKTCK ]]]

#
# BELOW is taken from m3_for_arty_a7 contraints... No idea how it is calculated
#

# Large input Tsu, as clock insertion delay is a lot shorter than datapath input delay.
set sw_in_tsu 8
set sw_in_max_delay [expr {$jtag_period - $sw_in_tsu}]
set sw_in_th  -1
set sw_out_tsu 5
set sw_out_th  -5
set debug_od 5.0
set debug_id 5.0

# SWDIO is driven at both ends by posedge clk.  The clock is sourced from the DAPLink board
# For input signals it could be either side of rising edge
# For output signals need to ensure the whole round trip is less than the period
set swdio [get_ports *SWDIO* ]
if {[ llength $swdio ]} {
   set_input_delay  -clock $cm3_dbg -add_delay -max $sw_in_max_delay $swdio
   set_input_delay  -clock $cm3_dbg -add_delay -min $sw_in_th        $swdio
   set_output_delay -clock $cm3_dbg -add_delay -max $sw_out_tsu      $swdio
   set_output_delay -clock $cm3_dbg -add_delay -min $sw_out_th       $swdio
}

# JTAG
# Note, these are optional ports and may be removed from the build
if {[ llength [get_ports TDI] ]} {
   set_input_delay  -clock $cm3_dbg -add_delay $debug_id [get_ports TDI ]
}
if {[ llength [get_ports nTRST] ]} {
   set_input_delay  -clock $cm3_dbg -add_delay $debug_id [get_ports nTRST ]
}
if {[ llength [get_ports TDO] ]} {
   set_output_delay  -clock $cm3_dbg -add_delay $debug_id [get_ports TDO ]
}
if {[ llength [get_ports TMS] ]} {
   set_output_delay  -clock $cm3_dbg -add_delay $debug_id [get_ports TMS ]
}
