/**
 *  FIFO tx arbiter - Muxes input compliant fifos into a single stream by decoding transaction
 * 
 *  parameters:
 *    SELMASK -  This is a bitmask that when matched will route data to fifo c1
 *               If not matched data will route to fifo c2.
 *    CNTMASK -  Mask pointing to contiguous CNT bits. Only 3 bits for count currently supported.
 *    DWIDTH  -  Data width
 *    AWIDTH  -  Address width of instantiated FIFOs.
 * 
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */

module fifo_arb_tx #(
                     parameter SELMASK  = 8'h80,
                     parameter CNTMASK  = 8'h70,
                     parameter DWIDTH   = 8,
                     parameter AWIDTH   = 3
                     )
   (
    // Global
    input               CLK,
    input               RESETn,
    // Input client 1
    input               c1_wren,
    input [DWIDTH-1:0]  c1_wrdata,
    output              c1_wrfull,
    // Input client 2
    input               c2_wren,
    input [DWIDTH-1:0]  c2_wrdata,
    output              c2_wrfull,
    // Output FIFO
    input               fifo_wrfull,
    output              fifo_wren,
    output [DWIDTH-1:0] fifo_wrdata        
    );

   // Import common definitions
   import host_fifo_pkg::*;

   // Calculate count shift
   localparam CSHIFT = $clog2 (CNTMASK) - FIFO_CNT_WIDTH;
   localparam CMASK  = (2**FIFO_CNT_WIDTH) - 1;
   
   // Internal write logic to each fifo
   wire                 c1_rden, c2_rden;
   wire                 c1_rdempty, c2_rdempty;
   wire [DWIDTH-1:0]    c1_rddata, c2_rddata;

   // Instantiate an internal fifo for each client
   fifo #(
          .DEPTH_WIDTH  (AWIDTH),
          .DATA_WIDTH   (DWIDTH)
          ) u_fifo1
     (
      .clk        (CLK),
      .rst        (~RESETn),
      .wr_en_i    (c1_wren),   // Client connection
      .wr_data_i  (c1_wrdata),
      .full_o     (c1_wrfull),
      .rd_data_o  (c1_rddata), // Arbiter connection
      .rd_en_i    (c1_rden),
      .empty_o    (c1_rdempty)
      );

   // Instantiate an internal fifo for each client
   fifo #(
          .DEPTH_WIDTH  (AWIDTH),
          .DATA_WIDTH   (DWIDTH)
          ) u_fifo2
     (
      .clk        (CLK),
      .rst        (~RESETn),
      .wr_en_i    (c2_wren),   // Client connection
      .wr_data_i  (c2_wrdata),
      .full_o     (c2_wrfull),
      .rd_data_o  (c2_rddata), // Arbiter connection
      .rd_en_i    (c2_rden),
      .empty_o    (c2_rdempty)
      );

   logic                          data_valid;
   logic                          c1_prden, c2_prden;
   logic                          c1_psel, c2_psel;
   logic [FIFO_PAYLOAD_WIDTH-1:0] dcnt;
   wire [DWIDTH-1:0]              data;
   wire                           hold;
   wire                           c1_sel, c2_sel;
   
   // Debug only
   //wire [DWIDTH-1:0]    cmd;
   //assign cmd = data_valid && (dcnt == 0) ? data : cmd;
   
   // Assign hold signals
   assign hold = (dcnt == 0) && ((data >> CSHIFT) & CMASK) ? 1 : 0;

   // FIFO selection
   assign c1_sel  = ~fifo_wrfull & (~c2_psel & (~c1_rdempty | (c1_psel & hold) | (c1_psel & (dcnt > 0))));
   assign c2_sel  = ~fifo_wrfull & (~c1_psel & (~c2_rdempty | (c2_psel & hold) | (c2_psel & (dcnt > 0))));
   assign c1_rden = c1_sel & ~c1_rdempty;
   assign c2_rden = c2_sel & ~c2_rdempty;
   
   // Data connected to current selected FIFO
   assign data = c1_prden ? c1_rddata : 
                 (c2_prden ? c2_rddata : 0);

   // Write to output fifo
   assign fifo_wren = ~fifo_wrfull & data_valid;
   assign fifo_wrdata = data;
   
   always @(posedge CLK)
     begin
        if (~RESETn)
          begin
             c1_prden <= 0;
             c2_prden <= 0;
             c1_psel <= 0;
             c2_psel <= 0;
             data_valid <= 0;
             dcnt <= 0;
          end
        else 
          begin

             // Assign cnt
             if (data_valid && (dcnt == 0))
               dcnt <= fifo_payload ((data >> CSHIFT) & CMASK);

             // Data is valid if either enable was asserted last cycle
             if (c1_rden | c2_rden)
               begin
                  data_valid <= 1;
                  if (dcnt)
                    dcnt <= dcnt - 1;
               end
             else
               data_valid <= 0;

             // Save previous rden
             c1_prden = c1_rden;
             c2_prden = c2_rden;
             c1_psel = c1_sel;
             c2_psel = c2_sel;
          end
     end
endmodule // fifo_arb_rx
