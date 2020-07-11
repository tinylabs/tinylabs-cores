# Pin placement
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { CLK_100M }];
set_property -dict { PACKAGE_PIN D9    IOSTANDARD LVCMOS33 } [get_ports { RESET }];   # BTN0

# JTAG
set_property -dict { PACKAGE_PIN P17   IOSTANDARD LVCMOS33 } [get_ports { TCK_SWDCLK }];  # IO13
set_property -dict { PACKAGE_PIN R17   IOSTANDARD LVCMOS33 } [get_ports { TDI }];         # IO12
set_property -dict { PACKAGE_PIN U18   IOSTANDARD LVCMOS33 } [get_ports { TDO }];         # IO11
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports { TMS_SWDIO }];   # IO10

# GPIOs
set_property -dict { PACKAGE_PIN B9    IOSTANDARD LVCMOS33 } [get_ports { GPIO[0] }]; # BTN2
set_property -dict { PACKAGE_PIN B8    IOSTANDARD LVCMOS33 } [get_ports { GPIO[1] }]; # BTN3
set_property -dict { PACKAGE_PIN H5    IOSTANDARD LVCMOS33 } [get_ports { GPIO[2] }]; # LED4
set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports { GPIO[3] }]; # LED6
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { GPIO[4] }]; # LED7
set_property -dict { PACKAGE_PIN E1    IOSTANDARD LVCMOS33 } [get_ports { GPIO[5] }]; # LED0-blue
set_property -dict { PACKAGE_PIN F6    IOSTANDARD LVCMOS33 } [get_ports { GPIO[6] }]; # LED0-grn
set_property -dict { PACKAGE_PIN G6    IOSTANDARD LVCMOS33 } [get_ports { GPIO[7] }]; # LED0-red


# Ignore timing on async reset
set_false_path -from [get_ports { RESET }]

# Untimed ports
set untimed_od 0.5
set untimed_id 0.5
set_input_delay  -clock [get_clocks hclk] -add_delay $untimed_id [get_ports RESET]
set_input_delay  -clock [get_clocks slow_clk] -add_delay $untimed_id [get_ports GPIO*]
set_output_delay -clock [get_clocks slow_clk] -add_delay $untimed_od [get_ports GPIO*]
