/**
 *  Common definitions for connecting IP to host FIFOs.
 * 
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */

package host_fifo_pkg;

   parameter FIFO_CNT_WIDTH = 3;
   parameter FIFO_PAYLOAD_WIDTH = 5;

   parameter [FIFO_CNT_WIDTH-1:0] 
     FIFO_D0  = 3'b000,
     FIFO_D1  = 3'b001,
     FIFO_D2  = 3'b010,
     FIFO_D4  = 3'b011,
     FIFO_D5  = 3'b100,
     FIFO_D6  = 3'b101,
     FIFO_D8  = 3'b110,
     FIFO_D16 = 3'b111;

   // Calculate bytes from cnt val
   function [FIFO_PAYLOAD_WIDTH-1:0] fifo_payload;
      input [FIFO_CNT_WIDTH-1:0] val;

      case (val)
        FIFO_D0:  fifo_payload = 0;
        FIFO_D1:  fifo_payload = 1;
        FIFO_D2:  fifo_payload = 2;
        FIFO_D4:  fifo_payload = 4;
        FIFO_D5:  fifo_payload = 5;
        FIFO_D6:  fifo_payload = 6;
        FIFO_D8:  fifo_payload = 8;
        FIFO_D16: fifo_payload = 16;
      endcase
   endfunction
endpackage
