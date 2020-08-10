/* Instantiate UART receiver/transmitter
 * Receiver requires first byte will be 0x55 ('U') which will be discarded
 * for autobaud calculation.
 * 
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */
module uart_transport
  (
   /* Clock */
   input        CLK,
   input        RESETn,
   /* Physical pins */
   output       TX_PIN,
   input        RX_PIN,
   /* FIFO interface */
   output       FIFO_WREN,
   input        FIFO_FULL,
   output [7:0] FIFO_DOUT,
   output       FIFO_RDEN,
   input        FIFO_EMPTY,
   input [7:0]  FIFO_DIN
);

   localparam CPB_WIDTH = 12;
   logic [CPB_WIDTH-1:0] cpb;

   // Instantiate receiver
   receiver #(.CPB_WIDTH  (CPB_WIDTH))
   u_uart_rx (
              .CLK     (CLK),
              .RESETn  (RESETn),
              .CPB     (cpb),
              .RX_PIN  (RX_PIN),
              .WRDATA  (FIFO_DOUT),
              .WREN    (FIFO_WREN),
              .WRFULL  (FIFO_FULL),
              .ERR     ()
              );
   
   // Instantiate transmitter
   transmitter #(.CPB_WIDTH  (CPB_WIDTH))
   u_uart_tx (
              .CLK     (CLK),
              .RESETn  (RESETn),
              .CPB     (cpb),
              .TX_PIN  (TX_PIN),
              .RDDATA  (FIFO_DIN),
              .RDEN    (FIFO_RDEN),
              .RDEMPTY (FIFO_EMPTY)
              );
   
endmodule
