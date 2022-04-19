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
#ifndef SERVER_H
#define SERVER_H

#include <pthread.h>
#include <stdint.h>
#include "readerwriterqueue.h"

class Server {

 private:
  const char *name;
  int sockfd;
  uint16_t port;
  pthread_t thread_id;
  bool debug;
  void Listen (void);
  void Send (int sockfd, char *buf, int len);

 protected:
  bool running;
  mc::ReaderWriterQueue<uint8_t> rx, tx;

 public:
  uint32_t period;
  Server (const char *name, uint32_t period, bool debug=0);
  virtual ~Server ();
  void Start (uint16_t port);
};

#endif /* SERVER_H */
