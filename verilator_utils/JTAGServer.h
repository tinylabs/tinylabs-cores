/**
 *  This is a simple TCP server that takes small bitbang packets
 *  and toggles the simulation input accordingly. The client is a
 *  custom openocd interface which allows full debugging of the
 *  target with minimal effort on our part.
 *
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2019
 */
#ifndef JTAGSERVER_H
#define JTAGSERVER_H

#include "Server.h"

class JTAGServer : public Server {
  
 public:
  JTAGServer (uint32_t period, bool debug=0) : Server ("JTAGServer", period, debug) {}
  ~JTAGServer () {}
  int doJTAGServer (uint64_t t, uint8_t *tck, uint8_t tdo, uint8_t *tdi, uint8_t *tms, uint8_t *srst);
};

#endif /* JTAGSERVER_H */
