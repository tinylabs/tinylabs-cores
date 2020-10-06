/**
 *  Verilator bench on top of swd_phy.sv - Test SWD phy
 *
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */

#include <signal.h>
#include <argp.h>
#include <verilator_utils.h>

#include "Vswd_phy.h"

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
  uint8_t  code;
  uint32_t data;
  uint8_t  parity;
} resp_t;

class swd_phy_tb : public VerilatorUtils {

private:
  Vswd_phy *top;
  bool _doCycle (void);
  resp_t resp;
  
public:
  swd_phy_tb ();
  ~swd_phy_tb ();
  bool doCycle (void);

  // Helper functions
  void Enable (void);
  void Disable (void);
  void SendReq (uint8_t len, uint8_t t0, uint8_t t1, uint64_t so);
  resp_t *GetResp (void);
};

static int parse_args (int argc, char **argv, swd_phy_tb *tb)
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

swd_phy_tb::swd_phy_tb (void) : VerilatorUtils (NULL)
{
  top = new Vswd_phy;

  // Enable trace
  top->trace (tfp, 99);
}

swd_phy_tb::~swd_phy_tb ()
{
  delete top;
}

bool swd_phy_tb::_doCycle (void)
{
  uint8_t tdo = 0;
  
  // Call base function
  if (!VerilatorUtils::doCycle() || done)
    return false;

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
  doJTAGClient (top->SWDCLK, &tdo, 0, top->SWDOE ? &top->SWDOUT : &top->SWDIN, top->SWDOE);

  // Continue
  return true;
}

bool swd_phy_tb::doCycle (void)
{
  // Two half cycles
  if (!_doCycle ()) return false;
  return _doCycle ();
}

void swd_phy_tb::Enable (void)
{
  top->ENABLE = 1;
  doCycle ();
}

void swd_phy_tb::Disable (void)
{
  top->ENABLE = 0;
  doCycle ();
}

static uint32_t reverseBits(uint32_t n) {
  n = (n >> 1) & 0x55555555 | (n << 1) & 0xaaaaaaaa;
  n = (n >> 2) & 0x33333333 | (n << 2) & 0xcccccccc;
  n = (n >> 4) & 0x0f0f0f0f | (n << 4) & 0xf0f0f0f0;
  n = (n >> 8) & 0x00ff00ff | (n << 8) & 0xff00ff00;
  n = (n >> 16) & 0x0000ffff | (n << 16) & 0xffff0000;
  return n;
}

void swd_phy_tb::SendReq (uint8_t len, uint8_t t0, uint8_t t1, uint64_t so)
{
  // Block if FIFO is full
  while (top->WRFULL)
    doCycle ();
  
  // Setup data
  top->WRDATA[0] = so & 0xffffffff;
  top->WRDATA[1] = (so >> 32) & 0xffffffff;
  top->WRDATA[2] = (t1 & 0x3f) | ((t0 & 0x3f) << 6) | ((len & 0x3f) << 12);

  // Set WriteEN
  top->WREN = 1;

  // Toggle clock
  doCycle ();

  // Done
  top->WREN = 0;
}

resp_t *swd_phy_tb::GetResp (void)
{
  // Cycle until response
  while (top->RDEMPTY)
    doCycle ();

  // Read response
  top->RDEN = 1;
  doCycle ();
  top->RDEN = 0;
  
  // Get data and return
  memset (&resp, 0, sizeof (resp));

  // Get length
  resp.len = (top->RDDATA & 0x3f);

  // Decode read
  if (resp.len == 36) {

    // Get parity
    resp.parity = (top->RDDATA >> 6) & 1;
    
    // Get data
    resp.data = reverseBits ((top->RDDATA >> 7) & 0xffffffff);
    
    // Get response code
    resp.code = (top->RDDATA >> 39) & 7;
  }
  else if (resp.len == 3) {
    resp.parity = 0;
    resp.data = 0;
    resp.code = (top->RDDATA >> 6) & 7;
  }
    
  return &resp;
}

uint64_t reg_write (bool APnDP, uint8_t addr, uint32_t data)
{
  uint8_t parity = 0;
  uint64_t v = 1; // Start bit

  // APnDP [1]
  if (APnDP)
    v |= (1 << 1);

  // Write bit [2] WRITE=0
  v |= (0 << 2);
  
  // Address [4:3]
  v |= ((addr >> 2) & 3) << 3;

  // Parity [5] RnW ^ APnDP ^ ADDR
  v |= (0 ^ ((addr >> 2) & 1) ^ ((addr >> 3) & 1) ^ APnDP) << 5;
  
  // Stop [6]
  v |= (0 << 6);
  
  // Park [7]
  v |= (1 << 7);

  // Data [40:9]
  v |= ((uint64_t)data << 9);
  
  // Data parity [41]
  while (data) {
    if (data & 1)
      parity ^= 1;
    data >>= 1;
  }
  v |= ((uint64_t)parity << 41);

  // Return dword
  return v;
}

uint64_t reg_read (bool APnDP, uint8_t addr)
{
  uint8_t parity = 0;
  uint64_t v = 1; // Start bit

  // APnDP [1]
  if (APnDP)
    v |= (1 << 1);

  // Write bit [2] READ=1
  v |= (1 << 2);
  
  // Address [4:3]
  v |= ((addr >> 2) & 3) << 3;

  // Parity [5] RnW ^ APnDP ^ ADDR
  v |= (1 ^ ((addr >> 2) & 1) ^ ((addr >> 3) & 1) ^ APnDP) << 5;
  
  // Stop [6]
  v |= (0 << 6);
  
  // Park [7]
  v |= (1 << 7);

  // Turnaround bit [8]

  // 3 bit response [11:9]

  // Turnaround bit 12

  // Return dword
  return v;
}

void dump_resp (resp_t *resp)
{
  if (resp->len == 36)
    printf ("R[%d%d%d] LEN=%d DATA=%08X PARITY=%s\n",
            resp->code >> 2, (resp->code >> 1) & 1, resp->code & 1,
            resp->len, resp->data,
            resp->parity == __builtin_parityl (resp->data) ? "OK" : "FAIL");
  else
    printf ("W[%d%d%d]\n", resp->code >> 2, (resp->code >> 1) & 1, resp->code & 1);
}

int main (int argc, char **argv)
{
  int i;
  resp_t *resp;
  
  swd_phy_tb *dut = new swd_phy_tb;
  

  // Parse args
  parse_args (argc, argv, dut);
  
  // Setup interrupt handler
  signal (SIGINT, &INTHandler);
  
  // Run through reset
  for (i = 0; i < RESET_TIME * 2; i++)
    dut->doCycle ();

  // Enable
  dut->Enable ();
  
  // Test line reset and SWD switch sequence
  dut->SendReq (60, 64, 64, 0x0fffffffffffffff);
  dut->SendReq (16, 64, 64, 0xe79e);
  dut->SendReq (62, 64, 64, 0x003fffffffffffff);
  
  // Read DP IDCode
  dut->SendReq (46, 8, 45, reg_read (0, 0));

  // Write DP CTRL/STAT
  dut->SendReq (46, 8, 12, reg_write (0, 4, 0x50000000));

  // Read DP CTRL/STAT
  dut->SendReq (46, 8, 45, reg_read (0, 4));

  // Get responses
  dump_resp (dut->GetResp ());
  dump_resp (dut->GetResp ());
  dump_resp (dut->GetResp ());

  // Disable interface
  dut->Disable ();

  // Add padding to end
  for (i = 0; i < 20; i++)
    dut->doCycle ();
  
  // Done
  delete dut;
  return 0;
}
