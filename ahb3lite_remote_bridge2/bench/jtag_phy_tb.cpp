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
  uint32_t data;
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

typedef enum {
              // No responses
              CMD_SHFT0      = 0,
              CMD_SHFT1      = 1,
              CMD_DATA       = 2,
              CMD_NOP        = 3,
              // Get response
              CMD_SHFT0_DATA = 4,
              CMD_SHFT1_DATA = 5,
              CMD_SHFT_DATA  = 6,
              CMD_COUNT      = 7,
} cmd_t;

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
  void SendReq (state_t state, cmd_t cmd, int len, uint32_t data);
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

void jtag_phy_tb::SendReq (state_t state, cmd_t cmd, int len, uint32_t data)
{
  // Block if FIFO is full
  while (top->WRFULL)
    doCycle ();
  
  // Setup data
  top->WRDATA = state;
  top->WRDATA |= (cmd << 4);
  top->WRDATA |= ((len & 0x3ff) << 7);
  top->WRDATA |= (data << 17);

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
  resp.len = top->RDDATA & 0x3f;
  resp.data = (top->RDDATA >> (6 + 32 - resp.len)) & 0xffffffff;
  return &resp;
}

void dump_resp (resp_t *resp)
{
  printf ("[%d] %X\n", resp->len, resp->data);
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

  // Reset state machine
  dut->SendReq (LOGIC_RESET, CMD_NOP, 5, 0);

  // Get IDCODE
  dut->SendReq (SHIFT_DR, CMD_SHFT0_DATA, 34, 0); 
  resp = dut->GetResp ();
  printf ("IDCode = %08X\n", resp->data);

  // Reset state machine
  dut->SendReq (LOGIC_RESET, CMD_NOP, 5, 0);

  // Clock out IRcode
  dut->SendReq (SHIFT_IR, CMD_SHFT0_DATA, 6, 0);
  dump_resp (dut->GetResp ());

  for (i = 1; i < 15; i++) {
    
    // Reset state machine
    dut->SendReq (LOGIC_RESET, CMD_NOP, 5, 0);

    // Write IR reg
    dut->SendReq (SHIFT_IR, CMD_DATA, 4, i);

    // Read DR
    dut->SendReq (SHIFT_DR, CMD_SHFT0_DATA, 34, 0); 
    dump_resp (dut->GetResp ());
  }
  
  // Disable interface
  dut->Disable ();

  // Add padding to end
  for (i = 0; i < 20; i++)
    dut->doCycle ();
  
  // Done
  delete dut;
  return 0;
}
