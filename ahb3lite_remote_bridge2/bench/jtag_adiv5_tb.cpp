/**
 *  Verilator bench on top of jtag_adiv5.sv - Test JTAG phy
 *
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */

#include <signal.h>
#include <argp.h>
#include <verilator_utils.h>

#include "Vjtag_adiv5.h"

#define RESET_TIME  10
static bool done = false;


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
typedef enum
  {
   OK = 4,
   WAIT = 2,
   FAULT = 1,
   NOCONNECT = 7
  } stat_t;

class jtag_adiv5_tb : public VerilatorUtils {

private:
  bool _doCycle (void);
  
public:
  Vjtag_adiv5 *top;
  jtag_adiv5_tb ();
  ~jtag_adiv5_tb ();
  bool doCycle (void);

  // Helper functions
  void Enable (void);
  void Disable (void);

  // DP/AP access
  void write (uint8_t addr,  bool APnDP, bool RnW, uint32_t data);
  uint32_t read (void);
  uint32_t dp_read (uint8_t addr);
  void dp_write (uint8_t addr, uint32_t data);
  uint32_t ap_read (uint8_t apsel, uint8_t addr);
  void ap_write (uint8_t apsel, uint8_t addr, uint32_t data);
};

static int parse_args (int argc, char **argv, jtag_adiv5_tb *tb)
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

jtag_adiv5_tb::jtag_adiv5_tb (void) : VerilatorUtils (NULL)
{
  top = new Vjtag_adiv5;

  // Enable trace
  top->trace (tfp, 99);
}

jtag_adiv5_tb::~jtag_adiv5_tb ()
{
  delete top;
}

bool jtag_adiv5_tb::_doCycle (void)
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
  
  // Call JTAG client function
  doJTAGClient (top->TCK, &top->TDO, top->TDI, &top->TMS);

  // Continue
  return true;
}

bool jtag_adiv5_tb::doCycle (void)
{
  // Two half cycles
  if (!_doCycle ()) return false;
  return _doCycle ();
}

void jtag_adiv5_tb::Enable (void)
{
  top->ENABLE = 1;
  doCycle ();
}

void jtag_adiv5_tb::Disable (void)
{
  top->ENABLE = 0;
  doCycle ();
}

void jtag_adiv5_tb::write (uint8_t addr, bool APnDP, bool RnW, uint32_t data)
{
  // Block if FIFO is full
  while (top->WRFULL)
    doCycle ();

  // Setup data
  top->WRDATA = (uint64_t)data << 8;
  top->WRDATA |= (addr & 0xfc);
  if (APnDP)
    top->WRDATA |= 1 << 1;
  if (RnW)
    top->WRDATA |= 1;
  
  // Set WriteEN
  top->WREN = 1;

  // Toggle clock
  doCycle ();

  // Clr WriteEN
  top->WREN = 0;
}  

uint32_t jtag_adiv5_tb::read (void)
{
  // Wait for response
  while (top->RDEMPTY)
    doCycle ();

  // Read
  top->RDEN = 1;
  doCycle ();
  top->RDEN = 0;
  
  // Check response
  if ((stat_t)(top->RDDATA & 7) != OK) {
    int i;
    printf ("read failed: %d\n", (int)(top->RDDATA & 7));
    for (i = 0; i < 100; i++)
      doCycle ();
    done = true; // Bail
  }
  
  // Return data
  return (uint32_t)((top->RDDATA >> 3) & 0xffffffff);
}  

void jtag_adiv5_tb::dp_write (uint8_t addr, uint32_t data)
{
  write (addr, 0, 0, data);
  if (addr != 0xc)
    read ();
}

uint32_t jtag_adiv5_tb::dp_read (uint8_t addr)
{
  write (addr, 0, 1, 0);
  return read ();
}


uint32_t jtag_adiv5_tb::ap_read (uint8_t apsel, uint8_t addr)
{
  // Write DP[8] = SELECT
  write (8, 0, 0, (apsel << 24) | addr);
  read ();
  
  // Read AP[addr]
  write (addr & 0xc, 1, 1, 0);
  
  // Get result
  return read ();
}

void jtag_adiv5_tb::ap_write (uint8_t apsel, uint8_t addr, uint32_t data)
{
  // Write DP[8] = SELECT
  write (8, 0, 0, (apsel << 24) | addr);
  read ();
  
  // Write AP[addr]
  write (addr & 0xc, 1, 0, data);
  read ();
}


int main (int argc, char **argv)
{
  int i;
  jtag_adiv5_tb *dut = new jtag_adiv5_tb;
  uint32_t val = 0;

  // Parse args
  parse_args (argc, argv, dut);
  
  // Setup interrupt handler
  signal (SIGINT, &INTHandler);
  
  // Run through reset
  for (i = 0; i < RESET_TIME * 2; i++)
    dut->doCycle ();
  
  // Enable
  dut->Enable ();

  // Reset
  dut->dp_write (0xc, 0);

  // Switch to JTAG
  dut->dp_write (0xc, 1);
  
  // Get IDCOde
  printf ("IDCODE=%08X\n", dut->dp_read (0));

  // Enable AP/DBGPWR
  dut->dp_write (4, 0x50000000);

  // Read back STAT
  val = dut->dp_read (4);
  printf ("CTRL/STAT=%08X\n", val); 
  if ((val & 0xf0000000) == 0xf0000000)
    printf ("PWR|DBG enabled\n");

  // Read IDR
  printf ("AP[0]=%08X\n", dut->ap_read (0, 0xfc));

  // Read BASE
  printf ("BASE=%08X\n", dut->ap_read (0, 0xf8));

  // Write AP[0] = CSW
  dut->ap_write (0, 0, 0xA2000002);

  // Write SCB_DHCSR to TAR
  dut->ap_write (0, 4, 0xE000EDF0);

  printf ("Halting processor... ");
  do {
    // Write HALT|DEBUGEN to DRW
    dut->ap_write (0, 0xc, 0xA05F0003);

    // Read DHCSR
  } while ((dut->ap_read (0, 0xc) & (1 << 17)) == 0);
  printf ("OK\n");

  // TAR = RAM
  dut->ap_write (0, 4, 0x20000000);

  // Write to RAM
  printf ("RAM test... ");
  dut->ap_write (0, 0xc, 0xdeadc0de);
  if (dut->ap_read (0, 0xc) == 0xdeadc0de)
    printf ("OK\n");
  else
    printf ("FAILED\n");

  // Add padding to end
  for (i = 0; i < 200; i++)
    dut->doCycle ();

  // Disable interface
  dut->Disable ();

  // Add padding to end
  for (i = 0; i < 20; i++)
    dut->doCycle ();
  
  // Done
  delete dut;
  return 0;
}
