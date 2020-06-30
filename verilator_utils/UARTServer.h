/**
 *  TCP server to take UART signals from host bridge and send them to host application
 *
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2019
 */
#ifndef UARTSERVER_H
#define UARTSERVER_H

#include "Server.h"

class UARTServer : public Server {
  
 public:
  UARTServer (uint32_t period, bool debug=0) : Server ("UARTServer", period, debug) {}
  ~UARTServer () {}
  int doUARTServer (uint64_t t, uint8_t tx, uint8_t *rx);
};

#endif /* UARTSERVER_H */
