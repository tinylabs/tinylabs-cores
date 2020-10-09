/**
 *  This is a simple TCP server that takes small bitbang packets
 *  and toggles the simulation input accordingly. The client is an
 *  openocd interface which allows full debugging of the
 *  target with minimal effort on our part.
 *
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2019
 */

#include "JTAGServer.h"

int JTAGServer::doJTAGServer (uint64_t t, uint8_t *tck, uint8_t tdo,
                              uint8_t *tdi, uint8_t *tms, uint8_t *srst)
{
  uint8_t cmd;

  // Only pass signals every period cycles
  if ((t % period) != 0)
    return true;
  
  // Pull a command off the receive queue
  if (tx.size_approx() && tx.try_dequeue (cmd)) {
    switch (cmd) {
      case '0' ... '7':
        *tdi = ((cmd - '0') & 1) ? 1 : 0;
        *tms = ((cmd - '0') & 2) ? 1 : 0;
        *tck = ((cmd - '0') & 4) ? 1 : 0;
        break;
      case 'r' ... 'u':
        /* Handle system reset - active low*/
        *srst = ((cmd - 'r') & 1) ? 0 : 1;
        break;
      case 'R':
        rx.enqueue (tdo ? '1' : '0');
        break;
      case 'S': /* Optional extension for SWD support (not supported in openocd) */
        {
          uint8_t c = '0';
          if (tdo)
            c += 1;
          if (*tms)
            c += 2;
          rx.enqueue (c);
          break;
        }
    }
  }

  return true;
}
