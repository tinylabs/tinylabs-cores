# Ignore message about ignoring assertions
set_msg_config -id {Synth 8-2898} -suppress
# Ignore non-standard IP output
set_msg_config -id {filemgmt 56-3} -suppress
# Ignore unknown vendor
set_msg_config -id {IP_Flow 19-3899} -suppress
# Ignore multiple defs of cm3_code_mux
set_msg_config -id {Synth 8-2490} -suppress
# Async reset used on sys bus on encrypted core - just ignore
set_msg_config -id {DRC REQP-1839} -suppress
# We cannot control the internal DSP pipelining (core is encrypted) ignore
set_msg_config -id {DRC DPIP-1} -suppress
set_msg_config -id {DRC DPOP-1} -suppress
set_msg_config -id {DRC DPOP-2} -suppress

# Just annoying
set_msg_config -id {Constraints 18-483} -suppress
set_msg_config -id {Vivado 12-584} -suppress

# Is this needed?
set_property IS_ENABLED 0 [get_drc_checks {DRC REQP-1839}]
set_property IS_ENABLED 0 [get_drc_checks {DRC DPIP-1}]
set_property IS_ENABLED 0 [get_drc_checks {DRC DPOP-1}]
set_property IS_ENABLED 0 [get_drc_checks {DRC DPOP-2}]

# Make sure top constraint is run first
reorder_files -fileset constrs_1 -front [get_files clocks.xdc]

# Set flags for files
set_property USED_IN_SYNTHESIS false [get_files pins.xdc]
