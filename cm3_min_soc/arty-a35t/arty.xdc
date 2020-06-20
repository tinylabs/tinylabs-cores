set_property CFGBVS Vcco [current_design]
set_property config_voltage 3.3 [current_design]

set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { CLK_100M }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { CLK_100M }];
# 10MHz max jtag clock
create_clock -add -name jtag_clk -period 100.00 -waveform {0 50} [get_ports { TCK_SWDCLK }];

# RESETn
set_property -dict { PACKAGE_PIN D9    IOSTANDARD LVCMOS33 } [get_ports { RESET }];

# JTAG
set_property -dict { PACKAGE_PIN P17   IOSTANDARD LVCMOS33 } [get_ports { TCK_SWDCLK }];  # IO13
set_property -dict { PACKAGE_PIN R17   IOSTANDARD LVCMOS33 } [get_ports { TDI }];         # IO12
set_property -dict { PACKAGE_PIN U18    IOSTANDARD LVCMOS33 } [get_ports { TDO }];        # IO11
set_property -dict { PACKAGE_PIN V17    IOSTANDARD LVCMOS33 } [get_ports { TMS_SWDIO }];  # IO10

# LED output
set_property -dict { PACKAGE_PIN H5    IOSTANDARD LVCMOS33 } [get_ports { LED }];
