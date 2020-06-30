/*
 * Hacky baud rate generator to divide a 50MHz clock into a 115200 baud
 * rx/tx pair where the rx clcken oversamples by 16x.
 */
module baud_rate_gen # (
                       parameter FREQ = 50000000,
                       parameter BAUD = 115200
                       ) 
   (
    input        clk,
	output logic rxclk_en,
	output logic txclk_en
    );
   
   localparam RX_ACC_MAX   = FREQ / (BAUD * 16);
   localparam TX_ACC_MAX   = FREQ / BAUD;
   localparam RX_ACC_WIDTH = $clog2(RX_ACC_MAX);
   localparam TX_ACC_WIDTH = $clog2(TX_ACC_MAX);
   logic [RX_ACC_WIDTH - 1:0] rx_acc;
   logic [TX_ACC_WIDTH - 1:0] tx_acc;
   
   assign rxclk_en = (rx_acc == 0) ? 1 : 0;
   assign txclk_en = (tx_acc == 0) ? 1 : 0;
   
   always @(posedge clk) 
     begin
	    if (rx_acc == RX_ACC_WIDTH'(RX_ACC_MAX) - 1)
	      rx_acc <= 0;
	    else
	      rx_acc <= rx_acc + 1;
        
	    if (tx_acc == TX_ACC_WIDTH'(TX_ACC_MAX) - 1)
	      tx_acc <= 0;
	    else
	      tx_acc <= tx_acc + 1;
     end

endmodule
