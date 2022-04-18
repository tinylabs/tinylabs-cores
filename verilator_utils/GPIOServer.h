/**
 *  TCP server to take GPIO signals from host bridge and send them to host application
 *
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2019
 */
#ifndef GPIOSERVER_H
#define GPIOSERVER_H

#include "Server.h"

class GPIOServer : public Server {

 private:
  uint64_t output;
  void SendOutputs (uint64_t output, size_t output_cnt);
  
 public:
  GPIOServer (uint32_t period, bool debug=0) : Server ("GPIOServer", period, debug) {}
  ~GPIOServer () {}
  int doGPIOServer (uint64_t t,
                    uint64_t *input, size_t input_cnt,
                    uint64_t output, size_t output_cnt); 
};

#endif /* GPIOSERVER_H */
