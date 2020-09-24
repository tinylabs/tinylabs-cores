/**
 *  Virtual SWD client - Connect to TCP server of SWD server
 *  forward local SWD signals over TCP to remote server via
 *  openocd bitbang protocol
 *
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */
#include <stdint.h>

class SWDClient {
 private:
  int swdsock = -1;
  
 public:
  SWDClient (int dummy) {}
  virtual ~SWDClient () { if (swdsock != -1) Stop (); }

  // Access functions
  void Start (uint16_t port);
  void Stop (void);
  void doSWDClient (uint64_t t, uint8_t swdclk, uint8_t swdout, uint8_t *swdin, uint8_t swdoe); 
};
