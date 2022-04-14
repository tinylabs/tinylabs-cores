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
#include <iostream>

#include "Server.h"
#include "err.h"

Server::Server (const char *name, uint32_t period, bool debug)
{
  this->name = name;
  this->period = period;
  this->debug = debug;
}

Server::~Server ()
{  
  // Wait for server to finish
  if (running) {
    running = 0;
    shutdown (sockfd, SHUT_RDWR);
    pthread_join (thread_id, NULL);
  }
}

void Server::Start (uint16_t port)
{
  int rv;

  /* Save port */
  this->port = port;

  /* Spawn new thread - Hacky but works... */
  #pragma GCC diagnostic ignored "-Wpmf-conversions"
  rv = pthread_create (&thread_id, NULL, (void *(*)(void *))&Server::Listen, this);
  if (rv)
    fail ("Failed to spawn thread!");
}

void Server::Send (int sockfd, char *buf, int len)
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
    fail ("ERROR writing to socket");
  }
}

void Server::Listen (void)
{
  int nsockfd, n, i, enable = 1;
  socklen_t clilen;
  char cmd[256], resp[256];
  struct sockaddr_in serv_addr, cli_addr;

  /* Set running */
  running = 1;
  
  /* First call to socket() function */
  sockfd = socket(AF_INET, SOCK_STREAM, 0);   
  if (sockfd < 0) {
    fail("ERROR opening socket");
  }
  if (setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &enable, sizeof(int)) < 0)
    fail("setsockopt(SO_REUSEADDR) failed");
 
  /* Initialize socket structure */
  bzero((char *) &serv_addr, sizeof(serv_addr));
  serv_addr.sin_family = AF_INET;
  serv_addr.sin_addr.s_addr = INADDR_ANY;
  serv_addr.sin_port = htons(this->port);

  /* Print message */
  printf ("%s listening on port: %u...\n", this->name, this->port);

  /* Now bind the host address using bind() call.*/
  if (bind(sockfd, (struct sockaddr *) &serv_addr, sizeof(serv_addr)) < 0) {
    fail("ERROR on binding");
  }
  
  /* Now start listening for the clients, here process will
   * go in sleep mode and will wait for the incoming connection
   */
  listen(sockfd,5);
  clilen = sizeof(cli_addr);
  
  /* Accept actual connection from the client */
 restart_connection:
  nsockfd = accept(sockfd, (struct sockaddr *)&cli_addr, &clilen);
  if (nsockfd < 0) {
    fail("ERROR on accept");
    goto done;
  }

  // Make socket non-blocking
  fcntl(nsockfd, F_SETFL, O_NONBLOCK);
  
  // Print client is connected
  printf ("%s connected.\n", this->name);
      
  // Continue to listen until connection is broken
  while (running) {

    /* If connection is established then start communicating */
    bzero (cmd, sizeof (cmd));
    n = read (nsockfd, cmd, sizeof (cmd) - 1);

    // Otherside closed connection
    if (n == 0) {
      close (nsockfd);
      printf ("Connection closed, restarting...\n");
      goto restart_connection;
    }
    
    /* Process packet */
    if (n > 0) {

      // NULL terminate
      if (debug) {
        cmd[n] = '\0';
        printf ("Recvd=[%s] len=%d\n", cmd, n);
      }

      // Process each command
      for (i = 0; i < n; i++)
        if (!tx.enqueue (cmd[i]))
          printf ("Failed to queue\n");
    }
    
    // Empty receive buffer
    if (rx.size_approx ()) {
      uint8_t val;

      // Create response packet
      for (i = 0; (i < sizeof (resp)) && rx.try_dequeue (val); i++)
        resp[i] = val;
      
      // Flush to socket
      Send (nsockfd, resp, i);
    }
  }
  
 done:
  printf ("%s terminating.\n", this->name);
}
