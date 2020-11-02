/**
 *  Virtual JTAG client - Connect to another simulator instance running JTAG server.
 *  Remote local JTAG master signals to remote JTAG client signals over openocd 
 *  bitbang protocol.
 *
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */

#include "JTAGClient.h"
#include "err.h"

#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

void JTAGClient::Start (uint16_t port)
{
  struct sockaddr_in a4;

  // Create socket
  jtagsock = socket (AF_INET, SOCK_STREAM, 0);
  if (jtagsock < 0)
    fail ("Unable to create jtagsock!");

  // Setup address
  inet_pton (AF_INET, "127.0.0.1", &a4.sin_addr);
  a4.sin_family = AF_INET;
  a4.sin_port = htons (port);

  // Connect to server
  if (connect (jtagsock, (const sockaddr *)&a4, sizeof (a4)) != 0)
    fail ("Failed to connect to localhost:%d", port);
  printf ("Connected to remote JTAG :%d\n", port);
}

void JTAGClient::Stop (void)
{
  close (jtagsock);
}

void JTAGClient::doJTAGClient (uint64_t t, uint8_t tck, uint8_t *tdo, uint8_t tdi, uint8_t *tms, uint8_t tmsoe)
{
  static uint8_t pclk = 0;
  uint8_t b;
  int rv;

  
  // JTAG clk is divided from sys clk
  // Only need action on transitions
  if (tck != pclk) {

    // Write JTAGIO state
    b = '0' | (tck << 2) | (*tms << 1) | tdi;
    rv = write (jtagsock, &b, 1);
    if (rv != 1)
      fail ("JTAGClient IO error");
    
    // Query TDI/TMS state
    b = 'S';
    rv = write (jtagsock, &b, 1);
    if (rv != 1)
      fail ("JTAGClient IO error");

    // Read state
    rv = read (jtagsock, &b, 1);
    if (rv != 1)
      fail ("JTAGClient IO error");

    // Get TDO
    if ((b - '0') & 1)
      *tdo = 1;
    else
      *tdo = 0;
    
    // Read from remote
    if (!tmsoe) {

      // Set tms/SWDIN
      if ((b - '0') & 2)
        *tms = 1;
      else
        *tms = 0;
    }

    // Save clock
    pclk = tck;
  }
}

