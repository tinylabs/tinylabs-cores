module uart_transport # (
                         parameter FREQ = 50000000,
                         parameter BAUD = 115200,
                         parameter OVERSAMPLE = 16
                        )
   (
    /* Clock */
	input wire         CLK,
    input wire         RESETn,
    /* Physical pins */
    output wire        TX_PIN,
	input wire         RX_PIN,
    /* FIFO interface */
    output logic       FIFO_WREN,
    input wire         FIFO_FULL,
    output logic [7:0] FIFO_DOUT,
    output logic       FIFO_RDEN,
    input wire         FIFO_EMPTY,
    input wire [7:0]   FIFO_DIN
);

   wire               rxclk_en, txclk_en;
   logic              tx_busy, tx_wren, tx_pending;
   logic              rx_rdy, rx_rdy_clr, rx_pending;
   
   /* Convert FIFO to expected interface */
   always @(posedge CLK)
     begin
        if (!RESETn)
          begin
             tx_pending <= 0;
             rx_pending <= 0;
          end
        else
          begin
             /* Simple transmit state machine */
             if (!tx_pending & !tx_busy & !FIFO_EMPTY)
               begin
                  // Read from FIFO
                  FIFO_RDEN  <= 1;
                  tx_pending <= 1;
               end
             else if (tx_busy)
               begin
                  tx_wren <= 0;
                  tx_pending <= 0;
               end
             else if (tx_pending)
               begin
                  FIFO_RDEN  <= 0;
                  tx_wren    <= 1;
               end
             
             /* Simple receive state machine */
             // Terminate
             if (rx_pending)
               begin
                  FIFO_WREN <= 0;
                  rx_pending <= 0;
                  rx_rdy_clr <= 0;
               end
             else if (rx_rdy)
               begin
                  
                  /* Detect overruns */
                  if (FIFO_FULL)
                    /* Do something here... */;
                  else
                    begin
                       FIFO_WREN <= 1;
                       rx_pending <= 1;
                    end
                  
                  // Clear ready signal
                  rx_rdy_clr <= 1;
               end
          end
     end
   
   baud_rate_gen #(
                   .FREQ       (FREQ),
                   .BAUD       (BAUD),
                   .OVERSAMPLE (OVERSAMPLE)
                   ) uart_baud (
                                .clk (CLK),
			                    .rxclk_en(rxclk_en),
			                    .txclk_en(txclk_en)
                                );
   transmitter uart_tx (
		                .clk     (CLK),
                        .din     (FIFO_DIN),
		                .tx      (TX_PIN),
		                .wr_en   (tx_wren),
		                .tx_busy (tx_busy),
		                .clken   (txclk_en)
                        );
   receiver #(
              .OVERSAMPLE (OVERSAMPLE)
              )
   uart_rx (
		    .clk     (CLK),
		    .data    (FIFO_DOUT),
            .rx      (RX_PIN),
		    .rdy     (rx_rdy),
		    .rdy_clr (rx_rdy_clr),
		    .clken   (rxclk_en)
            );

endmodule
