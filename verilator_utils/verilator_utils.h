#ifndef __VERILATOR_UTILS_H__
#define __VERILATOR_UTILS_H__

#include <stdint.h>
#include <verilated.h>
#include <verilated_fst_c.h>
#include "JTAGServer.h"
#include "UARTServer.h"
#include "JTAGClient.h"
#include "GPIOServer.h"
#include "GPIOClient.h"

extern struct argp verilator_utils_argp;

class VerilatorUtils {
public:
  VerilatorUtils(uint32_t *mem=NULL);
  ~VerilatorUtils();

  VerilatedFstC* tfp;

  JTAGServer *jtag_server = NULL;
  UARTServer *uart_server = NULL;
  JTAGClient *jtag_client = NULL;
  GPIOClient *gpio_client = NULL;
  GPIOServer *gpio_server = NULL;
  
  bool doCycle();
  bool doGPIOServer (uint64_t *input, size_t input_cnt, uint64_t output, size_t output_cnt);
  bool doGPIOClient (uint64_t *input, size_t input_cnt, uint64_t output, size_t output_cnt);
  bool doJTAGServer (uint8_t *tck, uint8_t tdo, uint8_t *tdi, uint8_t *tms, uint8_t *srst=NULL);
  bool doUARTServer (uint8_t tx, uint8_t *rx);
  bool doJTAGClient (uint8_t tck, uint8_t *tdo, uint8_t tdi, uint8_t *tms, uint8_t tmsoe = true);
  uint64_t getTime() { return t; }
  uint64_t getTimeout() { return timeout; }
  bool getFstDump() { return fstDump; }
  uint64_t getFstDumpStart() { return fstDumpStart; }
  uint64_t getFstDumpStop() { return fstDumpStop; }
  char *getFstFileName() { return fstFileName; }
  bool getJtagEnable() { return jtagServerEnable; }
  int getJtagPort() { return jtagServerPort; }

  static int parseOpts(int key, char *arg, struct argp_state *state);

private:
  uint64_t t;
  uint64_t timeout;

  bool fstDump;
  uint64_t fstDumpStart;
  uint64_t fstDumpStop;
  char *fstFileName;
  bool fstDumping;

  bool jtagServerEnable;
  int jtagServerPort;
  bool uartServerEnable;
  int uartServerPort;
  bool jtagClientEnable;
  int jtagClientPort;
  bool gpioServerEnable;
  int gpioServerPort;
  bool gpioClientEnable;
  int gpioClientPort;
  
  uint32_t *mem;

  bool loadElf(char *fileName);
  bool loadBin(char *fileName);
};

#endif
