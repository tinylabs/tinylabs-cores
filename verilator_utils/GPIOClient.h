/**
 *  Virtual GPIO client - Connect to TCP server of GPIO server
 *  forward local GPIO signals over TCP to remote server.
 *
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */
#include <stdint.h>
#include <stdlib.h>

class GPIOClient {
 private:
  int gpiosock = -1;
  uint64_t output;
  void SendOutputs (uint64_t output, size_t output_cnt);
  
 public:
  GPIOClient (int dummy) {}
  virtual ~GPIOClient () { if (gpiosock != -1) Stop (); }

  // Access functions
  void Start (uint16_t port);
  void Stop (void);
  void doGPIOClient (uint64_t t,
                     uint64_t *input, size_t input_cnt,
                     uint64_t output, size_t output_cnt);
};
