# tinylabs-cores
This repo contains fusesoc compatible cores and a sample ARM Cortex-M3 system on chip (SoC) for the Arty-A35 created from these cores.
## Dependencies
* [fusesoc](https://fusesoc.readthedocs.io/en/rtd/tutorials/1-getting_started.html)\
`pip install fusesoc`\
`fusesoc init`
* Verilator (if running sim)\
apt-get install verilator
* [Vivado](https://www.xilinx.com/support/download.html) (if synthesizing example SoC)
* [ARM DesignStart Eval (CM3)](https://developer.arm.com/ip-products/designstart/eval)\
_This is currently mirrored and linked from the fusesoc core so no need to download unless it's taken down_
* [ARM DesignStart for FPGA (CM3)](https://developer.arm.com/ip-products/designstart/fpga) - Optional for encrypted CM3 synthesis
## Preparation
* Create an empty directory\
`mkdir fusesoc-test; cd fusesoc-test`
* Add the tinylabs-cores library\
`fusesoc library add tinylabs-cores https://github.com/tinylabs/tinylabs-cores.git`
* Source vivado at login to add path to environment\
`source /opt/path/to/vivado/settings64.sh` in ~/.profile\
_Alternatively you can add vivado-settings:path to the .core file_
## Building and running the simulation
* Compile and run the verilated model\
`fusesoc run --target=sim cm3_min_soc && gtkwave ./build/cm3_min_soc_0.1/sim-verilator/sim.vcd`\
You can inspect the top level GPIO_O signal to see the blinking GPIO
## Synthesize for the [Arty board (A35T)](https://www.xilinx.com/products/boards-and-kits/arty.html)
There are two targets for synthesis corresponding to the swappable Cortex-M3 cores released by ARM. The AT421 package contains an obsfucated/flattened core which is fully synthesizable but has fixed parameters and cannot be optimized by the EDA tools. We always use this for simulation but it can also be synthesiszed and run on an FPGA. The second core is in the AT426 package which contains encrypted RTL that can only be read by Vivado. Through trial and error I determined the interface was _almost_ identical which means we can blindly instantiate it and allow Vivado to decrypt it during compilation.
