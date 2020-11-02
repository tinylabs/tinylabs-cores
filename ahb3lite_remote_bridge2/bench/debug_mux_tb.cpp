/**
 *  Verilator bench on top of debug_mux.sv - Test JTAG phy
 *
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */

#include <signal.h>
#include <argp.h>
#include <verilator_utils.h>

#include "Vdebug_mux.h"

#define RESET_TIME  10
static bool done = false;

// Valid commands
#define CMD_DR_WRITE       0
#define CMD_DR_READ        1
#define CMD_DR_WRITE_AUTO  2
#define CMD_DR_READ_AUTO   3
#define CMD_IR_WRITE       4
#define CMD_IR_READ        5
#define CMD_IR_WRITE_AUTO  6
#define CMD_IR_READ_AUTO   7

static void INTHandler (int signal)
{
  printf("\nCaught ctrl-c\n");
  done = true;
}

static int parse_opt (int key, char *arg, struct argp_state *state)
{
  switch (key) {
    case ARGP_KEY_INIT:
      state->child_inputs[0] = state->input;
      break;
      // Add parsing custom options here
  }
  return 0;
}

// Response status
typedef enum {
   OK = 4,
   WAIT = 2,
   FAULT = 1,
   NOCONNECT = 7
} stat_t;

typedef struct {
  uint8_t  len;
  uint64_t data;
} resp_t;

class debug_mux_tb : public VerilatorUtils {

private:
  bool _doCycle (void);
  resp_t resp;
  
public:
  Vdebug_mux *top;
  debug_mux_tb ();
  ~debug_mux_tb ();
  bool doCycle (void);

  // DP/AP access
  void write (uint8_t addr,  bool APnDP, bool RnW, uint32_t data);
  uint32_t read (void);
  uint32_t dp_read (uint8_t addr);
  void dp_write (uint8_t addr, uint32_t data);
  uint32_t ap_read (uint8_t apsel, uint8_t addr);
  void ap_write (uint8_t apsel, uint8_t addr, uint32_t data);

  // Test interface
  int test_if (bool JTAGnSWD);

  // JTAG direct
  int JTAG_Direct (void);
  void JTAGReq (uint8_t cmd, int len, uint64_t data);
  resp_t *JTAGResp (void);
};

static int parse_args (int argc, char **argv, debug_mux_tb *tb)
{
  struct argp_option options[] =
    {
     // Add custom options here
     { 0 }
  };
  struct argp_child child_parsers[] =
    {
     { &verilator_utils_argp, 0, "", 0 },
     { 0 }
  };
  struct argp argp = { options, parse_opt, 0, 0, child_parsers };
  return argp_parse (&argp, argc, argv, 0, 0, tb);
}

debug_mux_tb::debug_mux_tb (void) : VerilatorUtils (NULL)
{
  top = new Vdebug_mux;

  // Enable trace
  top->trace (tfp, 99);
}

debug_mux_tb::~debug_mux_tb ()
{
  delete top;
}

bool debug_mux_tb::_doCycle (void)
{
  uint8_t tdo = 0;
  
  // Call base function
  if (!VerilatorUtils::doCycle() || done)
    exit (-1);

  // Control reset
  if (getTime () > RESET_TIME)
    top->RESETn = 1;
  else
    top->RESETn = 0;
  
  // Eval
  top->eval ();

  // Flip clocks
  top->CLK = !top->CLK;
  top->PHY_CLK = !top->PHY_CLK;
  top->PHY_CLKn = !top->PHY_CLK;
  
  // Call JTAG client function
  doJTAGClient (top->TCK, &top->TDO, top->TDI, top->TMSOE ? &top->TMSOUT : &top->TMSIN, top->TMSOE);

  // Continue
  return true;
}

bool debug_mux_tb::doCycle (void)
{
  // Two half cycles
  if (!_doCycle ()) return false;
  return _doCycle ();
}

void debug_mux_tb::JTAGReq (uint8_t cmd, int len, uint64_t data)
{
  // Block if FIFO is full
  while (top->JTAG_WRFULL)
    doCycle ();
  
  // Setup data
  top->JTAG_WRDATA[0] = (cmd & 7);
  top->JTAG_WRDATA[0] |= ((len & 0xfff) << 3);
  top->JTAG_WRDATA[0] |= ((data & 0x1ffff) << 15); // 17bits
  top->JTAG_WRDATA[1] = (data >> 17) & 0xffffffff; // 32bits
  top->JTAG_WRDATA[2] = (data >> 49) & 0x7fff;     // 15bits
  
  // Set WriteEN
  top->JTAG_WREN = 1;

  // Toggle clock
  doCycle ();

  // Done
  top->JTAG_WREN = 0;
}

resp_t *debug_mux_tb::JTAGResp (void)
{
  // Cycle until response
  while (top->JTAG_RDEMPTY)
    doCycle ();

  // Read response
  top->JTAG_RDEN = 1;
  doCycle ();
  top->JTAG_RDEN = 0;

  // Save in response
  resp.len = (top->JTAG_RDDATA[0] & 0x3f);
  if (resp.len == 0)
    resp.len = 64;
  resp.data = (top->JTAG_RDDATA[0] >> 6) |
    ((uint64_t)top->JTAG_RDDATA[1] << 26) |
    (((uint64_t)top->JTAG_RDDATA[2] & 0x3f) << 58);

  // Right justify response
  resp.data >>= (64 - resp.len);
  return &resp;
}

void dump_resp (resp_t *resp)
{
  printf ("[%d] %08X%08X\n", resp->len, uint32_t((resp->data >> 32) & 0xffffffff), uint32_t(resp->data & 0xffffffff));
}

void debug_mux_tb::write (uint8_t addr, bool APnDP, bool RnW, uint32_t data)
{
  // Block if FIFO is full
  while (top->ADIv5_WRFULL)
    doCycle ();

  // Setup data
  top->ADIv5_WRDATA = (uint64_t)data << 4;
  top->ADIv5_WRDATA |= (addr & 3) << 2;
  if (APnDP)
    top->ADIv5_WRDATA |= 1 << 1;
  if (RnW)
    top->ADIv5_WRDATA |= 1;
  
  // Set WriteEN
  top->ADIv5_WREN = 1;

  // Toggle clock
  doCycle ();

  // Clr WriteEN
  top->ADIv5_WREN = 0;
}  

uint32_t debug_mux_tb::read (void)
{
  // Wait for response
  while (top->ADIv5_RDEMPTY)
    doCycle ();

  // Read
  top->ADIv5_RDEN = 1;
  doCycle ();
  top->ADIv5_RDEN = 0;
  
  // Check response
  if ((stat_t)(top->ADIv5_RDDATA & 7) != OK) {
    int i;
    printf ("read failed: %d\n", (int)(top->ADIv5_RDDATA & 7));
    for (i = 0; i < 100; i++)
      doCycle ();
    done = true; // Bail
  }
  
  // Return data
  return (uint32_t)((top->ADIv5_RDDATA >> 3) & 0xffffffff);
}  

void debug_mux_tb::dp_write (uint8_t addr, uint32_t data)
{
  write ((addr >> 2) & 3, 0, 0, data);
  if (addr != 0xc)
    read ();
}

uint32_t debug_mux_tb::dp_read (uint8_t addr)
{
  write ((addr >> 2) & 3, 0, 1, 0);
  return read ();
}


uint32_t debug_mux_tb::ap_read (uint8_t apsel, uint8_t addr)
{
  // Write DP[8] = SELECT
  write (2, 0, 0, (apsel << 24) | addr);
  read ();
  
  // Read AP[addr]
  write ((addr >> 2) & 3, 1, 1, 0);

  // Get result
  return read ();
}

void debug_mux_tb::ap_write (uint8_t apsel, uint8_t addr, uint32_t data)
{
  // Write DP[8] = SELECT
  write (2, 0, 0, (apsel << 24) | addr);
  read ();
  
  // Write AP[addr]
  write ((addr >> 2) & 3, 1, 0, data);
  read ();
}

int debug_mux_tb::test_if (bool JTAGnSWD)
{
  int i;
  uint32_t val = 0;

  printf ("Testing %s interface...\n", JTAGnSWD ? "JTAG" : "SWD");
  
  // Disable JTAG direct
  top->JTAG_DIRECT = 0;
  
  // Select interface
  top->JTAGnSWD = JTAGnSWD;
  doCycle ();

  // Reset
  dp_write (0xc, 0);

  // Switch to JTAG
  dp_write (0xc, 1);
  
  // Get IDCOde
  printf ("IDCODE=%08X\n", dp_read (0));

  // Enable AP/DBGPWR
  dp_write (4, 0x50000000);

  // Read back STAT
  val = dp_read (4);
  printf ("CTRL/STAT=%08X\n", val); 
  if ((val & 0xf0000000) == 0xf0000000)
    printf ("PWR|DBG enabled\n");

  // Read IDR
  printf ("AP[0]=%08X\n", ap_read (0, 0xfc));

  // Read BASE
  printf ("BASE=%08X\n", ap_read (0, 0xf8));

  // Write AP[0] = CSW
  ap_write (0, 0, 0xA2000002);

  // Write SCB_DHCSR to TAR
  ap_write (0, 4, 0xE000EDF0);

  printf ("Halting processor... ");
  do {
    // Write HALT|DEBUGEN to DRW
    ap_write (0, 0xc, 0xA05F0003);

    // Read DHCSR
  } while ((ap_read (0, 0xc) & (1 << 17)) == 0);
  printf ("OK\n");

  // TAR = RAM
  ap_write (0, 4, 0x20000000);

  // Write to RAM
  printf ("RAM test... ");
  ap_write (0, 0xc, 0xdeadc0de);
  if (ap_read (0, 0xc) == 0xdeadc0de)
    printf ("OK\n");
  else
    printf ("FAILED\n");
  printf ("\n");
  
  // Add padding to end
  for (i = 0; i < 100; i++)
    doCycle ();

  return 0;
}

int debug_mux_tb::JTAG_Direct (void)
{
  printf ("Testing JTAG direct interface\n");
  
  // Set direct interface
  top->JTAG_DIRECT = 1;
  doCycle ();
  
  // Send RESET
  JTAGReq (CMD_DR_WRITE, 0, 0);
  
  // Switch to JTAG
  JTAGReq (CMD_IR_WRITE, 0, 0);

  // Read IDCode
  JTAGReq (CMD_DR_READ, 32, 0);
  printf ("IDCODE=%08X\n", (uint32_t)JTAGResp()->data);
  
  return 0;
}

int main (int argc, char **argv)
{
  int i;
  debug_mux_tb *dut = new debug_mux_tb;

  // Parse args
  parse_args (argc, argv, dut);
  
  // Setup interrupt handler
  signal (SIGINT, &INTHandler);
  
  // Run through reset
  for (i = 0; i < RESET_TIME * 2; i++)
    dut->doCycle ();

  // Test SWD
  dut->test_if (0);
  
  // Test JTAG
  dut->test_if (1);

  // Test SWD
  dut->test_if (0);

  // Test JTAG direct
  dut->JTAG_Direct ();
  
  // Add padding to end
  for (i = 0; i < 20; i++)
    dut->doCycle ();
  
  // Done
  delete dut;
  return 0;
}
