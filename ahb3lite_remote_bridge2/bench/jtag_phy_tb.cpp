/**
 *  Verilator bench on top of jtag_phy.sv - Test JTAG phy
 *
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */

#include <signal.h>
#include <argp.h>
#include <verilator_utils.h>

#include "Vjtag_phy.h"

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

typedef struct {
  uint8_t  len;
  uint64_t data;
} resp_t;

typedef enum {
              RUNTEST_IDLE = 0,
              LOGIC_RESET  = 8,
              SELECT_DR    = 1,
              CAPTURE_DR   = 4,
              SHIFT_DR     = 2,
              EXIT1_DR     = 5,
              PAUSE_DR     = 6,
              EXIT2_DR     = 7,
              UPDATE_DR    = 3,
              SELECT_IR    = 9,
              CAPTURE_IR   = 12,
              SHIFT_IR     = 10,
              EXIT1_IR     = 13,
              PAUSE_IR     = 14,
              EXIT2_IR     = 15,
              UPDATE_IR    = 11,
} state_t;

class jtag_phy_tb : public VerilatorUtils {

private:
  bool _doCycle (void);
  resp_t resp;
  
public:
  Vjtag_phy *top;
  jtag_phy_tb ();
  ~jtag_phy_tb ();
  bool doCycle (void);

  // Helper functions
  void Enable (void);
  void Disable (void);
  void SendReq (uint8_t cmd, int len, uint64_t data);
  resp_t *GetResp (void);
};

static int parse_args (int argc, char **argv, jtag_phy_tb *tb)
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

jtag_phy_tb::jtag_phy_tb (void) : VerilatorUtils (NULL)
{
  top = new Vjtag_phy;

  // Enable trace
  top->trace (tfp, 99);
}

jtag_phy_tb::~jtag_phy_tb ()
{
  delete top;
}

bool jtag_phy_tb::_doCycle (void)
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

bool jtag_phy_tb::doCycle (void)
{
  // Two half cycles
  if (!_doCycle ()) return false;
  return _doCycle ();
}

void jtag_phy_tb::Enable (void)
{
  top->ENABLE = 1;
  doCycle ();
}

void jtag_phy_tb::Disable (void)
{
  top->ENABLE = 0;
  doCycle ();
}

// Valid commands
#define CMD_DR_WRITE       0
#define CMD_DR_READ        1
#define CMD_DR_WRITE_AUTO  2
#define CMD_DR_READ_AUTO   3
#define CMD_IR_WRITE       4
#define CMD_IR_READ        5
#define CMD_IR_WRITE_AUTO  6
#define CMD_IR_READ_AUTO   7

void jtag_phy_tb::SendReq (uint8_t cmd, int len, uint64_t data)
{
  // Block if FIFO is full
  while (top->WRFULL)
    doCycle ();
  
  // Setup data
  top->WRDATA[0] = (cmd & 7);
  top->WRDATA[0] |= ((len & 0xfff) << 3);
  top->WRDATA[0] |= ((data & 0x1ffff) << 15); // 17bits
  top->WRDATA[1] = (data >> 17) & 0xffffffff; // 32bits
  top->WRDATA[2] = (data >> 49) & 0x7fff;     // 15bits
  
  // Set WriteEN
  top->WREN = 1;

  // Toggle clock
  doCycle ();

  // Done
  top->WREN = 0;
}

resp_t *jtag_phy_tb::GetResp (void)
{
  // Cycle until response
  while (top->RDEMPTY)
    doCycle ();

  // Read response
  top->RDEN = 1;
  doCycle ();
  top->RDEN = 0;

  // Save in response
  resp.len = (top->RDDATA[0] & 0x3f);
  if (resp.len == 0)
    resp.len = 64;
  resp.data = (top->RDDATA[0] >> 6) | ((uint64_t)top->RDDATA[1] << 26) | (((uint64_t)top->RDDATA[2] & 0x3f) << 58);

  // Right justify response
  resp.data >>= (64 - resp.len);
  return &resp;
}

void dump_resp (resp_t *resp)
{
  printf ("[%d] %08X%08X\n", resp->len, uint32_t((resp->data >> 32) & 0xffffffff), uint32_t(resp->data & 0xffffffff));
}

int device_count (jtag_phy_tb *dut)
{
  int i;
  uint64_t dr[64];
  
  // Put chain in bypass
  dut->SendReq (CMD_IR_WRITE_AUTO, 128, -1);
  
  // Write zero to chain
  dut->SendReq (CMD_DR_WRITE_AUTO, 64, 0);

  // Write one then zero
  dut->SendReq (CMD_DR_READ, 64, 1);
    
  // Get responses
  for (i = 0; i < 1; i++)
    dr[i] = dut->GetResp ()->data;
  
  // Check length
  for (i = 0; i < 64; i++)
    if (dr[i>>6] & (1 << (i & 0x3f)))
      break;

  // Return scan chain length
  return (i == 64) ? -1 : i;
}

int main (int argc, char **argv)
{
  int i;
  resp_t *resp;
  
  jtag_phy_tb *dut = new jtag_phy_tb;
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

  // Make sure we're in reset
  for (i = 0; i < 5; i++)
    dut->doCycle ();

  // Get device count
  printf ("Device count = %d\n", device_count (dut));
  
  // Send IDCOde IR
  dut->SendReq (CMD_IR_WRITE, 4, 0xE);

  // Read IDcode
  dut->SendReq (CMD_DR_READ, 32, 0);
  resp = dut->GetResp ();
  printf ("IDCODE=%08X\n", (uint32_t)(resp->data & 0xffffffff));

  // Add padding to end
  for (i = 0; i < 100; i++)
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
