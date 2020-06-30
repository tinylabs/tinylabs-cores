/**
 *  Convert host bridge UART transport to TCP for debugging simulation
 *
 *  NOTE: This will only work if (HOST_FREQ/BAUD == 32)!
 *
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */

#include "UARTServer.h"
#include <stdio.h>
#include <stdint.h>

typedef enum {
              STATE_IDLE = 0,
              STATE_DATA,
              STATE_STOP,
              STATE_DONE,
              STATE_MAX_ENUM
} state_t;

int UARTServer::doUARTServer (uint64_t t, uint8_t tx_pin, uint8_t *rx_pin)
{
  static state_t tx_state = STATE_IDLE, rx_state = STATE_IDLE;
  static uint64_t tx_start = 0, rx_start = 0;
  static uint8_t rxc = 0, rcnt = 0;
  static uint8_t txc = 0, tcnt = 0;

  // Return if server not started or odd ticks
  if (!running || (t & 1))
    return true;

  // TX state machine
  if (!tx_start || (((t - tx_start) % 64) == 0)) {
    switch (tx_state) {
      
      // Look for start bit
      case STATE_IDLE:
        if (!tx_pin) {
          tx_state = STATE_DATA;
          tx_start = t;
        }
        break;
        
        // Handle data bits
      case STATE_DATA:
        rxc >>= 1;
        if (tx_pin)
          rxc |= 0x80;
        rcnt++;
        if (rcnt == 8)
          tx_state = STATE_STOP;
        break;
        
        // Check stop bit
      case STATE_STOP:
        if (!tx_pin)
          printf ("Stop bit error!\n");
        
        // Add to transmit queue
        //printf ("=> %02X\n", rxc);
        rx.enqueue (rxc);
        
        // Reset variables
        tx_state = STATE_IDLE;
        rxc = rcnt = 0;
        tx_start = 0;
        break;
    }
  }

  // Receive state machine
  if (!rx_start || (((t - rx_start) % 64) == 0)) {
    switch (rx_state) {
      
      // Check for new data
      case STATE_IDLE:
        if (tx.size_approx() && tx.try_dequeue (txc)) {
          *rx_pin = 0;
          rx_state = STATE_DATA;
          rx_start = t;
        }
        break;

        // Transmit data
      case STATE_DATA:
        if (txc & 1)
          *rx_pin = 1;
        else
          *rx_pin = 0;
        txc >>= 1;
        tcnt++;
        if (tcnt == 8)
          rx_state = STATE_STOP;
        break;
        
      // Send stop bit
      case STATE_STOP:
        *rx_pin = 1;
        rx_state = STATE_DONE;
        break;

        // Reset state machine
      case STATE_DONE:
        rx_state = STATE_IDLE;
        txc = tcnt = 0;
        rx_start = 0;
        break;
    }
  }
  return true;
}

