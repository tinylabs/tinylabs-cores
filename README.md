# tinylabs-cores
This repo contains fusesoc compatible cores and a sample ARM Cortex-M3 system on chip (SoC) for the Arty-A35 created from these cores.
## Dependencies
* [fusesoc](https://fusesoc.readthedocs.io/en/rtd/tutorials/1-getting_started.html)\
`pip install fusesoc`\
`fusesoc init`
* Verilator (if running sim)\
apt-get install verilator
* [Vivado](https://www.xilinx.com/support/download.html) (if synthesizing example SoC)
* [ARM AT421 DesignStart Eval (CM3)](https://developer.arm.com/ip-products/designstart/eval)\
_This is currently mirrored and linked from the fusesoc core so no need to download unless it's taken down_
* [ARM AT426 DesignStart for FPGA (CM3)](https://developer.arm.com/ip-products/designstart/fpga) - Optional for encrypted CM3 synthesis
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
### Building synth_arty (AT421 obsfucated core)
`fusesoc run --target=synth_arty cm3_min_soc`\
On completion this will flash the Arty board if plugged in. You should see LD4 blinking.
### Building synth_arty_full (AT426 encrypted core)
* Create empty directory\
`mkdir AT426; cd AT426`
* Copy core file from tinylabs-cores\
`wget https://raw.githubusercontent.com/tinylabs/tinylabs-cores/master/cm3_full/cm3_full.core`
* Download and unzip AT426 from ARM (link above)
* Go back to fusesoc-test and add library to fusesoc\
`cd ../`\
`fusesoc library add cm3_full $PWD/AT426`
* Synthesize using encrypted CM3\
`fusesoc run --target=synth_arty_full cm3_min_soc`\
Again, you should see LD4 blinking
#### AT421 Attributes
* Plaintext interface
* Compatible with Verilator
* IRQ_CNT fixed at 16
* Runs up to 30MHz (in my tests)
* Uses 73% of LUTs
* Synthesizable on non-Xilinx FPGAs
#### AT426 Attributes
* EDA optimizable
* Runs up to 50MHz (in my tests)
* Uses 59% of LUTs
* Up to 240 IRQs supported (not tested)
* Synthesizable ONLY with Vivado
### Help! Things that need fixing:
* Implied RAM generates a bunch of warnings in Vivado, would be nice to know if these are valid and if so how to fix them.
* The top level timings constraints could be improved. They may be altogether wrong, any help here would be much appreciated.
* A fusesoc generator for the APB bus would be useful to add additional APB peripherals.
* Additional core targets for popular boards that are supported by the fusesoc (edalize) backend would be great.
* More testing all around.
## Licensing
My understanding [not a lawyer(TM)] is that the AT426 core is OK for commercial use if used on Xilinx 7-series parts. However, many of the other components from RoaLogic (ahb3lite_interconnect, ahb3lite_memory, ahb3lite_apb_brige, apb4_gpio) have a non-commercial clause. With some work these components could be replaced.\
\
Except as represented in this agreement, all work product by TinyLabs is provided ​“AS IS”. Other than as provided in this agreement, TinyLabs makes no other warranties, express or implied, and hereby disclaims all implied warranties, including any warranty of merchantability and warranty of fitness for a particular purpose.

