/*
 * mor1kx-generic system Verilator testbench
 *
 * Author: Olof Kindgren <olof.kindgren@gmail.com>
 * Author: Franck Jullien <franck.jullien@gmail.com>
 *
 * This program is free software; you can redistribute  it and/or modify it
 * under  the terms of  the GNU General  Public License as published by the
 * Free Software Foundation;  either version 2 of the  License, or (at your
 * option) any later version.
 *
 */

#include <stdint.h>
#include <signal.h>
#include <argp.h>
#include <verilator_tb_utils.h>

#include "Vcm3_min_soc.h"

static bool done;

#define RESET_TIME		4

vluint64_t main_time = 0;       // Current simulation time
// This is a 64-bit integer to reduce wrap over issues and
// allow modulus.  You can also use a double, if you wish.

double sc_time_stamp () {       // Called by $time in Verilog
  return main_time;           // converts to double, to match
  // what SystemC does
}

void INThandler(int signal)
{
	printf("\nCaught ctrl-c\n");
	done = true;
}

static int parse_opt(int key, char *arg, struct argp_state *state)
{
	switch (key) {
	case ARGP_KEY_INIT:
		state->child_inputs[0] = state->input;
		break;
	// Add parsing of custom options here
	}

	return 0;
}

static int parse_args(int argc, char **argv, VerilatorTbUtils* tbUtils)
{
	struct argp_option options[] = {
		// Add custom options here
		{ 0 }
	};
	struct argp_child child_parsers[] = {
		{ &verilator_tb_utils_argp, 0, "", 0 },
		{ 0 }
	};
	struct argp argp = { options, parse_opt, 0, 0, child_parsers };

	return argp_parse(&argp, argc, argv, 0, 0, tbUtils);
}

int main(int argc, char **argv, char **env)
{
	uint32_t insn = 0;
	uint32_t ex_pc = 0;

	Verilated::commandArgs(argc, argv);

	Vcm3_min_soc* top = new Vcm3_min_soc;
	VerilatorTbUtils* tbUtils =
      new VerilatorTbUtils(top->cm3_min_soc__DOT__u_rom__DOT__ram_inst__DOT__genblk2__DOT__genblk2__DOT__ram_inst__DOT__mem_array);
    
	parse_args(argc, argv, tbUtils);

	signal(SIGINT, INThandler);

    top->CLK = 0;
    top->PORESETn = 0;
	top->trace(tbUtils->tfp, 99);

	while (tbUtils->doCycle() && !done) {
		if (tbUtils->getTime() > RESET_TIME)
			top->PORESETn = 1;

		top->eval();
        top->CLK = !top->CLK;
		tbUtils->doJTAG(&top->TMS_SWDIN, &top->TDI, &top->TCK_SWDCLK, top->TDO);
	}

	//printf("Simulation ended at PC = %08x (%lu)\n",
	//       ex_pc, tbUtils->getTime());

	delete tbUtils;
	exit(0);
}
