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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <netdb.h>
#include <netinet/in.h>
#include <sys/fcntl.h>

#include "JTAGServer.h"
#include <iostream>

// Buffer this many bits before responding
#define RESP_THRESHOLD 33    

JTAGServer::JTAGServer (uint32_t period, bool debug)
{
  this->period = period;
  this->debug = debug;
}

JTAGServer::~JTAGServer ()
{
  // Kill processes, return resources
}

pthread_t JTAGServer::Start (uint16_t port)
{
  int rv;
  pthread_t thread_id;

  /* Save port */
  this->port = port;

  /* Spawn new thread - Hacky but works... */
  #pragma GCC diagnostic ignored "-Wpmf-conversions"
  rv = pthread_create (&thread_id, NULL, (void *(*)(void *))&JTAGServer::Listen, this);
  if (rv)
    perror ("Failed to spawn thread!");
  return thread_id;
}

void JTAGServer::Send (int sockfd, char *buf, int len)
{
  int rv;

  /* Debug */
  if (debug) {
    buf[len] = '\0';
    printf ("resp=[%s]\n", buf);
  }
  
  /* Write a response to the client */
  rv = write (sockfd, buf, len);
  if (rv < 0) {
    perror ("ERROR writing to socket");
    exit (1);
  }
}

void JTAGServer::Listen (void)
{
  int sockfd, nsockfd;
  socklen_t clilen;
  char cmd[256], resp[256];
  struct sockaddr_in serv_addr, cli_addr;
  int n, i, ridx = 0;
  int cnt = 0;
  
  /* First call to socket() function */
  sockfd = socket(AF_INET, SOCK_STREAM, 0);   
  if (sockfd < 0) {
    perror("ERROR opening socket");
    exit(1);
  }
   
  /* Initialize socket structure */
  bzero((char *) &serv_addr, sizeof(serv_addr));
  serv_addr.sin_family = AF_INET;
  serv_addr.sin_addr.s_addr = INADDR_ANY;
  serv_addr.sin_port = htons(this->port);

  /* Print message */
  printf ("JTAG server on port: %u...\n", this->port);

  /* Now bind the host address using bind() call.*/
  if (bind(sockfd, (struct sockaddr *) &serv_addr, sizeof(serv_addr)) < 0) {
    perror("ERROR on binding");
    exit(1);
  }
  
  /* Now start listening for the clients, here process will
   * go in sleep mode and will wait for the incoming connection
   */
  listen(sockfd,5);
  clilen = sizeof(cli_addr);
  
  /* Accept actual connection from the client */
  nsockfd = accept(sockfd, (struct sockaddr *)&cli_addr, &clilen);
  if (nsockfd < 0) {
    perror("ERROR on accept");
    exit(1);
  }

  // Make socket non-blocking
  fcntl(nsockfd, F_SETFL, O_NONBLOCK);
  
  // Print client is connected
  printf ("JTAG Client connected.\n");
      
  // Continue to listen until connection is broken
  while (1) {

    /* If connection is established then start communicating */
    bzero (cmd, sizeof (cmd));
    n = read (nsockfd, cmd, sizeof (cmd) - 1);

    // Otherside closed connection
    if (n == 0)
      break;

    // Get receive queue size
    size_t rx_size = rx.size_approx ();
    if (rx_size > 100) {
      printf ("Anomaly detected. sz=%lu\n", rx_size);
    }
    
    /* Use openocd remote bitbang interface */
    if (n > 0) {

      // NULL terminate
      if (debug) {
        cmd[n] = '\0';
        printf ("Recvd=[%s] len=%d\n", cmd, n);
      }

      // Process each command
      for (i = 0; i < n; i++) {
        switch (cmd[i]) {
          case '0' ... '7':
            tx.enqueue (cmd[i] - '0' | (CMD_SIGNAL << 6));
            break;
            
          case 'r' ... 'u':
            tx.enqueue ((cmd[i] - 'r') | (CMD_RESET << 6));
            break;
            
          case 'R':
            tx.enqueue (CMD_TDO << 6);
            break;

            // Extension to handle SWD protocol over bitbang
          case 'S':
            tx.enqueue (CMD_SWDO << 6);
            break;
            
            /* Ignore LED commands */
          default:
          case 'b':
          case 'B':
            break;
        }
      }
    }

    // Empty receive buffer
    else if ((rx.size_approx () > RESP_THRESHOLD) ||
             (rx.size_approx () && ((cnt % 10000) == 0))) {

      uint8_t val;
      
      // Clear buffer
      i = 0;
      while ((i < sizeof (resp)) &&
             rx.try_dequeue (val)) {
        resp[i] = val ? '1' : '0';
        i++;
      }
      
      // Flush to socket
      Send (nsockfd, resp, i);
    }

    // Increment count
    cnt++;
  }
}

int JTAGServer::doJTAGServer (uint64_t t, uint8_t *tms, uint8_t *tdi, uint8_t *tck, uint8_t tdo, uint8_t swdo,  uint8_t *srst)
{
  uint8_t cmd;

  // Only pass signals every period cycles
  if ((t % period) != 0)
    return true;
  
  // Pull a command off the receive queue
  if (tx.size_approx() && tx.try_dequeue (cmd)) {
    switch ((cmd >> 6) & 3) {
      case CMD_SIGNAL:
        *tdi = (cmd & 1) ? 1 : 0;
        *tms = (cmd & 2) ? 1 : 0;
        *tck = (cmd & 4) ? 1 : 0;
        break;
      case CMD_RESET:
        /* Handle system reset - active low*/
        *srst = (cmd & 1) ? 0 : 1;
        break;
      case CMD_TDO:
        rx.enqueue (tdo);
        break;
      case CMD_SWDO: /* Optional extension for SWD support (not supported in openocd) */
        rx.enqueue (swdo);
        break;
    }
  }

  return true;
}
