/* Instantiate simple 8N1 UART receiver/transmitter. Connect to external dual-clock FIFO.
 * 
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */
module uart_fifo
  (
   /* Clock */
   input              CLK,
   input              RESETn,
   /* Physical pins */
   output             TX_PIN,
   input              RX_PIN,
   /* FIFO interface */
   output logic       FIFO_WREN,
   input              FIFO_FULL,
   output [7:0]       FIFO_DOUT,
   output logic       FIFO_RDEN,
   input              FIFO_EMPTY,
   input [7:0]        FIFO_DIN,
   /* Dropped bytes due to FIFO congestion */
   output logic [9:0] DROPPED
);

   localparam TIMER_BITS = 4;

   // Local logic
   logic        tx_busy, dvalid, wren;
   
   // Read when not empty or busy
   assign FIFO_RDEN = !FIFO_EMPTY & !dvalid;

   // Write when valid and not full
   assign FIFO_WREN = wren & !FIFO_FULL;
      
   // Data valid on next cycle
   always @(posedge CLK)
     if (!RESETn)
       begin
          dvalid <= 0;
          DROPPED <= 0;
       end
     else
       begin
          if (FIFO_RDEN)
            dvalid <= 1;
          else if (!tx_busy)
            dvalid <= 0;

          if (wren & FIFO_FULL)
            DROPPED <= DROPPED + 1;

       end
   
   // Instantiate receiver
   rxuartlite #(
                .TIMER_BITS      (TIMER_BITS),
                .CLOCKS_PER_BAUD (4) // 12Mbaud @ 48MHz
                )
   u_uart_rx (
              .i_clk     (CLK),
              .i_uart_rx (RX_PIN),
              .o_wr      (wren),
              .o_data    (FIFO_DOUT)
              );

   // Instantiate transmitter
   txuartlite #(
                .TIMING_BITS  (TIMER_BITS),
                .CLOCKS_PER_BAUD (4) // 12Mbaud @ 48MHz
                )
   u_uart_tx (
              .i_clk     (CLK),
              .i_wr      (dvalid),
              .i_data    (FIFO_DIN),
              .o_uart_tx (TX_PIN),
              .o_busy    (tx_busy));
   
endmodule
