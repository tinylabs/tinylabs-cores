/**
 *  Virtual GPIO client - Connect to another simulator instance running GPIO server.
 *  shuttle GPIO signals between client and server
 *
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */

#include "GPIOClient.h"
#include "err.h"

#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>

void GPIOClient::Start (uint16_t port)
{
  struct sockaddr_in a4;

  // Create socket
  gpiosock = socket (AF_INET, SOCK_STREAM, 0);
  if (gpiosock < 0)
    fail ("Unable to create gpiosock!");

  int status = fcntl(gpiosock, F_SETFL, fcntl(gpiosock, F_GETFL, 0) | O_NONBLOCK);
  if (status == -1)
    printf ("Error calling fcntl\n");

  // Setup address
  inet_pton (AF_INET, "127.0.0.1", &a4.sin_addr);
  a4.sin_family = AF_INET;
  a4.sin_port = htons (port);

  // Connect to server
  if (connect (gpiosock, (const sockaddr *)&a4, sizeof (a4)) != 0)
    fail ("Failed to connect to localhost:%d", port);
  printf ("Connected to remote GPIO :%d\n", port);
}

void GPIOClient::Stop (void)
{
  close (gpiosock);
}

void GPIOClient::SendOutputs (uint64_t output, size_t output_cnt)
{
  int i, idx = 0;
  uint8_t data[65];

  // Check for output changes
  if (output != this->output) {

    // Find change
    for (i = 0; i < output_cnt; i++) {
      if ((output & (1 << i)) != (this->output & (1 << i))) {

        // Generate data output
        if (output & (1 << i))
          data[idx++] = (i & 0x7F) | 0x80;
        else
          data[idx++] = (i & 0x7F);
      }
    }
    
    // Add flush
    data[idx++] = 0xFF;
    
    // Send update
    if (write (gpiosock, data, idx) != idx)
      printf ("Failed to send GPIO %u\n", i);

    // Update cache
    this->output = output;
  }
}


void GPIOClient::doGPIOClient (uint64_t t,
                               uint64_t *input, size_t input_cnt,
                               uint64_t output, size_t output_cnt)

  {
  uint8_t cmd, off;
  static bool init = false;

  // Initialize first run
  if (!init) {
    int i;
    
    // Flip all bits to force send
    this->output = ~output;
    
    // Send outputs
    SendOutputs (output, output_cnt);
    init = true;
  }
  else {
    // Check output differences
    SendOutputs (output, output_cnt);
  }

  // Non-blocking read
  while (read (gpiosock, &cmd, 1) == 1) {

    // Break on flush
    if (cmd == 0xFF)
      break;
    
    // Get signal offset
    off = cmd & 0x7F;
    if (off < input_cnt) {
      if (cmd & 0x80)
        *input |= (1 << off);
      else
        *input &= ~(1 << off);
    }
  }
}
