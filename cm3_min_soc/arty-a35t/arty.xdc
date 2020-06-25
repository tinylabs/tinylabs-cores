# Setup global configs
set_property CFGBVS Vcco [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# Pin placement
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { CLK_100M }];
set_property -dict { PACKAGE_PIN D9    IOSTANDARD LVCMOS33 } [get_ports { RESET }];

# JTAG
set_property -dict { PACKAGE_PIN P17   IOSTANDARD LVCMOS33 } [get_ports { TCK_SWDCLK }];  # IO13
set_property -dict { PACKAGE_PIN R17   IOSTANDARD LVCMOS33 } [get_ports { TDI }];         # IO12
set_property -dict { PACKAGE_PIN U18   IOSTANDARD LVCMOS33 } [get_ports { TDO }];         # IO11
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports { TMS_SWDIO }];   # IO10

# GPIOs
set_property -dict { PACKAGE_PIN H5    IOSTANDARD LVCMOS33 } [get_ports { GPIO0 }];

# System clock
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { CLK_100M }];

# 10MHz JTAG/SWD clock
create_clock -add -name jtag_clk -period 100.00 -waveform {0 50} [get_ports { TCK_SWDCLK }];

# Ignore timing on async reset
set_false_path -from [get_ports { RESET }]

# Get period of HCLK (pll output)
set hclk_period [get_property PERIOD [get_clocks hclk ]]
set jtag_period [get_property PERIOD [get_clocks jtag_clk ]]

# DAP and CPU are asynchronous, this should ensure that everything is setup for CDC
set_max_delay -from [get_clocks hclk] -to [get_clocks jtag_clk] -datapath_only [expr { $hclk_period - 1 }]
set_max_delay -from [get_clocks jtag_clk] -to [get_clocks hclk] -datapath_only [expr { $hclk_period - 1 }]

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

# Create virtual clock for IO
create_clock -name slow_clk -period 100.0

# SWDIO
# SWDIO is driven at both ends by posedge clk.  The clock is sourced from the DAPLink board
# For input signals it could be either side of rising edge
# For output signals need to ensure the whole round trip is less than the period
set_input_delay  -clock [get_clocks jtag_clk] -add_delay -max $sw_in_max_delay [get_ports TMS_SWDIO]
set_input_delay  -clock [get_clocks jtag_clk] -add_delay -min $sw_in_th        [get_ports TMS_SWDIO]
set_output_delay -clock [get_clocks jtag_clk] -add_delay -max $sw_out_tsu      [get_ports TMS_SWDIO]
set_output_delay -clock [get_clocks jtag_clk] -add_delay -min $sw_out_th       [get_ports TMS_SWDIO]

# JTAG
# Note, these are optional ports and may be removed from the build
set_input_delay  -clock [get_clocks jtag_clk] -add_delay $debug_id [get_ports TDI]
#set_input_delay  -clock [get_clocks jtag_clk] -add_delay $debug_id [get_ports nTRST] # Not used
set_output_delay -clock [get_clocks jtag_clk] -add_delay $debug_od [get_ports TDO]

# Untimed ports
set untimed_od 0.5
set untimed_id 0.5
set_input_delay  -clock [get_clocks hclk] -add_delay $untimed_id [get_ports RESET]
set_input_delay  -clock [get_clocks slow_clk] -add_delay $untimed_id [get_ports GPIO*]
set_output_delay -clock [get_clocks slow_clk] -add_delay $untimed_od [get_ports GPIO*]
