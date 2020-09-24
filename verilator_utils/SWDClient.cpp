/**
 *  Virtual SWD client - Connect to another simulator instance running JTAG server.
 *  Remote local SWD master signals to remote SWD client signals over openocd 
 *  bitbang protocol.
 *
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */

#include "SWDClient.h"
#include "err.h"

#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

void SWDClient::Start (uint16_t port)
{
  struct sockaddr_in a4;

  // Create socket
  swdsock = socket (AF_INET, SOCK_STREAM, 0);
  if (swdsock < 0)
    fail ("Unable to create swdsock!");

  // Setup address
  inet_pton (AF_INET, "127.0.0.1", &a4.sin_addr);
  a4.sin_family = AF_INET;
  a4.sin_port = htons (port);

  // Connect to server
  if (connect (swdsock, (const sockaddr *)&a4, sizeof (a4)) != 0)
    fail ("Failed to connect to localhost:%d", port);
  printf ("Connected to remote JTAG :%d\n", port);
}

void SWDClient::Stop (void)
{
  close (swdsock);
}

void SWDClient::doSWDClient (uint64_t t, uint8_t swdclk, uint8_t swdout, uint8_t *swdin, uint8_t swdoe)
{
  static uint8_t pclk = 0;
  uint8_t b;
  int rv;
  
  // SWD clk is divided from sys clk
  // Only need action on transitions
  if (swdclk != pclk) {

    // Write SWDIO state
    b = '0' | (swdclk << 2) | (swdout << 1);
    rv = write (swdsock, &b, 1);
    if (rv != 1)
      fail ("SWDClient IO error");
    
    // Read from remote
    if (!swdoe) {

      // Query state
      b = 'S';
      rv = write (swdsock, &b, 1);
      if (rv != 1)
        fail ("SWDClient IO error");

      // Read SWDIN
      rv = read (swdsock, &b, 1);
      if (rv != 1)
        fail ("SWDClient IO error");

      // Set signal
      *swdin = (b == '1') ? 1 : 0;
    }

    // Save clock
    pclk = swdclk;
  }
}

