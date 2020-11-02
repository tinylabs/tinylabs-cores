/**
 *  Virtual JTAG client - Connect to TCP server of JTAG server
 *  forward local JTAG signals over TCP to remote server via
 *  openocd bitbang protocol
 *
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */
#include <stdint.h>

class JTAGClient {
 private:
  int jtagsock = -1;
  
 public:
  JTAGClient (int dummy) {}
  virtual ~JTAGClient () { if (jtagsock != -1) Stop (); }

  // Access functions
  void Start (uint16_t port);
  void Stop (void);
  void doJTAGClient (uint64_t t, uint8_t tck, uint8_t *tdo, uint8_t tdi, uint8_t *tms, uint8_t tmsoe);
};
