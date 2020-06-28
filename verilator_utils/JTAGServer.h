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

#include <pthread.h>
#include <stdint.h>
#include "readerwriterqueue.h"

// JTAG commands
typedef enum {
              CMD_SIGNAL = 0,
              CMD_RESET  = 1,
              CMD_TDO    = 2,
              CMD_SWDO   = 3
} jtag_cmd_t;

class JTAGServer {

 private:
  mc::ReaderWriterQueue<uint8_t> rx, tx;
  uint16_t port;
  bool debug;
  uint32_t period;
  void Listen (void);
  void Send (int sockfd, char *buf, int len);
  
 public:
  JTAGServer (uint32_t period, bool debug=0);
  ~JTAGServer ();
  pthread_t Start (uint16_t port);
  int doJTAGServer (uint64_t t, uint8_t *tms, uint8_t *tdi, uint8_t *tck, uint8_t tdo, uint8_t swdo, uint8_t *srst);
};

#endif /* JTAGSERVER_H */
