#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <argp.h>
#include <elf-loader.h>
#include "verilator_utils.h"

#define VCD_DEFAULT_NAME "../sim.vcd"

VerilatorUtils::VerilatorUtils(uint32_t *mem)
  : mem(mem), t(0), timeout(0), vcdDump(false), vcdDumpStart(0), vcdDumpStop(0),
    vcdFileName((char *)VCD_DEFAULT_NAME),
    jtagServerEnable(false), jtagServerPort(2345),
    uartServerEnable(false), uartServerPort(7777) {
  tfp = new VerilatedVcdC;
  jtag_server = new JTAGServer (8);
  uart_server = new UARTServer (4); // period=oversample rate
    
  Verilated::traceEverOn(true);
  printf("Tracing on\n");
}

VerilatorUtils::~VerilatorUtils() {
    if (vcdDumping)
      tfp->close();
    // Stop JTAG server
    delete jtag_server;
    delete uart_server;
}

bool VerilatorUtils::doJTAGServer (uint8_t *tms, uint8_t *tdi, uint8_t *tck, uint8_t tdo, uint8_t swdo, uint8_t *srst) {
  uint8_t dummy;
  if (!srst)
    srst = &dummy; 
  if (jtagServerEnable)
    jtag_server->doJTAGServer (t, tms, tdi, tck, tdo, swdo, srst);
  return true;
}

bool VerilatorUtils::doUARTServer (uint8_t tx, uint8_t *rx)
{
  if (uartServerEnable)
    uart_server->doUARTServer (t, tx, rx);
  return true;
}

bool VerilatorUtils::doCycle() {
  if (vcdDumpStop && t >= vcdDumpStop) {
    if (vcdDumping) {
      printf("VCD dump stopped (%lu)\n", t);
      tfp->close();
    }
    vcdDumping = false;
  } else if (vcdDump && t >= vcdDumpStart) {
    if (!vcdDumping) {
      printf("VCD dump started (%lu)\n", t);
      tfp->open(vcdFileName);
    }
    vcdDumping = true;
  }

  if (vcdDumping)
    tfp->dump((vluint64_t)t);

  if(timeout && t >= timeout) {
    printf("Timeout reached\n");
    return false;
  }

  if (Verilated::gotFinish()) {
    printf("Caught $finish()\n");
    return false;
  }

  t++;
  return true;
}

bool VerilatorUtils::loadElf(char *fileName) {
  uint8_t *bin_data;
  int size;

  printf("Loading %s\n", fileName);
  bin_data = load_elf_file(fileName, &size);
  if (bin_data == NULL) {
    printf("Error loading elf file\n");
    return false;
  }

  for (int i = 0; i < size; i += 4)
    this->mem[i/4] = read_32(bin_data, i);

  free(bin_data);

  return true;
}

bool VerilatorUtils::loadBin(char *fileName) {
  uint8_t *bin_data;
  int size;
  FILE *bin_file = fopen(fileName, "rb");

  printf("Loading %s\n", fileName);

  if (bin_file == NULL) {
    printf("Error opening bin file\n");
    return false;
  }
  fseek(bin_file, 0, SEEK_END);
  size = ftell(bin_file);
  rewind(bin_file);
  bin_data = (uint8_t *)malloc(size);
  if (fread(bin_data, 1, size, bin_file) != size) {
    printf("Error reading bin file\n");
    return false;
  }

  for (int i=0; i < size; i+=4)
    this->mem[i/4] = read_32(bin_data, i);

  free(bin_data);

  return true;
}

#define OPT_TIMEOUT 512
#define OPT_ELFLOAD 513
#define OPT_BINLOAD 514

static struct argp_option options[] = {
  { 0, 0, 0, 0, "Simulation control:", 1 },
  { "timeout", OPT_TIMEOUT, "VAL", 0, "Stop the sim at VAL" },
  { "elf-load", OPT_ELFLOAD, "FILE", 0, "Load program from ELF FILE" },
  { "bin-load", OPT_BINLOAD, "FILE", 0, "Load program from binary FILE" },
  { 0, 0, 0, 0, "VCD generation:", 2 },
  { "vcd", 'v', "FILE", OPTION_ARG_OPTIONAL, "Enable and save VCD to FILE" },
  { "vcdstart", 's', "VAL", 0, "Delay VCD generation until VAL" },
  { "vcdstop", 't', "VAL", 0, "Terminate VCD generation at VAL" },
  { 0, 0, 0, 0, "Remote debugging:", 3 },
  { "jtag-server", 'j', "PORT", OPTION_ARG_OPTIONAL, "Enable openocd JTAG server, opt. specify PORT" },
  { "uart-server", 'u', "PORT", OPTION_ARG_OPTIONAL, "Enable uart host server, opt. specify PORT" },
  { 0 },
};

struct argp verilator_utils_argp = {options, VerilatorUtils::parseOpts,
                                    0, 0};

int VerilatorUtils::parseOpts(int key, char *arg, struct argp_state *state) {
  VerilatorUtils *utils = static_cast<VerilatorUtils *>(state->input);

  switch (key) {
  case OPT_TIMEOUT:
    utils->timeout = strtol(arg, NULL, 10);
    break;

  case OPT_ELFLOAD:
    utils->loadElf(arg);
    break;

  case OPT_BINLOAD:
    utils->loadBin(arg);
    break;

  case 'v':
    utils->vcdDump = true;
    if (arg)
      utils->vcdFileName = arg;
    break;

  case 's':
    utils->vcdDumpStart = strtol(arg, NULL, 10);
    break;

  case 't':
    utils->vcdDumpStop = strtol(arg, NULL, 10);
    break;

  case 'j':
    utils->jtagServerEnable = true;
    if (arg)
      utils->jtagServerPort = atoi(arg);
    utils->jtag_server->Start (utils->jtagServerPort);
    break;

  case 'u':
    utils->uartServerEnable = true;
    if (arg)
      utils->uartServerPort = atoi (arg);
    utils->uart_server->Start (utils->uartServerPort);
    break;
    
  default:
    return ARGP_ERR_UNKNOWN;
  }

  return 0;
}
