/**
 *  Receive GPIO signals over socket. Set received signal for inputs.
 *  Return outputs if changed.
 *
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */

#include "GPIOServer.h"
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <string.h>

void GPIOServer::SendOutputs (uint64_t output, size_t output_cnt)
{
  int i;
  
  // Check for output changes
  if (output != this->output) {

    // Find change
    for (i = 0; i < output_cnt; i++) {

      if ((output & (1 << i)) != (this->output & (1 << i))) {

        // Send output
        if (output & (1 << i)) {
          if (!rx.enqueue ((i & 0x7F) | 0x80))
            printf ("Failed to send GPIO %u\n", i);
        }
        else {
          if (!rx.enqueue (i & 0x7F))
            printf ("Failed to send GPIO %u\n", i);
        }
      }
    }

    // Update cache
    this->output = output;
  }
}

int GPIOServer::doGPIOServer (uint64_t t,
                              uint64_t *input, size_t input_cnt,
                              uint64_t output, size_t output_cnt)
{
  uint8_t cmd, off;
  static bool init = false;
  
  // Return if server not started or odd ticks
  if (!running)
    return true;

  // Initialize first run
  if (!init) {
    int i;

    // Flip all bits so everything gets sent
    this->output = ~output;
    
    // Send outputs
    SendOutputs (output, output_cnt);
    init = true;
  }
  else
    // Check output differences
    SendOutputs (output, output_cnt);  

  // Check if there are new commands
  while (tx.size_approx() && tx.try_dequeue(cmd)) {

    // Stop at flush command
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

  return true;
}

