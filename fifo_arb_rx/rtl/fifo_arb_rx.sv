/**
 *  FIFO rx arbiter - Checks against bitmask and passes signals to one of two clients.
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

module fifo_arb_rx #(
                     parameter SELMASK  = 8'h80,
                     parameter CNTMASK  = 8'h70,
                     parameter DWIDTH   = 8,
                     parameter AWIDTH   = 3
                     )
   (
    // Global
    input               CLK,
    input               RESETn,
    // Output client 1
    input               c1_rden,
    output              c1_rdempty,
    output [DWIDTH-1:0] c1_rddata,
    // Output client 2
    input               c2_rden,
    output              c2_rdempty,
    output [DWIDTH-1:0] c2_rddata,
    // Input FIFO
    output              fifo_rden,
    input               fifo_rdempty,
    input [DWIDTH-1:0]  fifo_rddata        
    );

   // Import common definitions
   import host_fifo_pkg::*;
   
   // Calculate count shift
   localparam CSHIFT = $clog2 (CNTMASK) - FIFO_CNT_WIDTH;
   localparam CMASK  = (2**FIFO_CNT_WIDTH) - 1;
   
   // Internal write logic to each fifo
   wire                 c1_wren, c2_wren;
   wire                 c1_wrfull, c2_wrfull;
   wire [DWIDTH-1:0]    c1_wrdata, c2_wrdata;

   // Instantiate an internal fifo for each client
   fifo #(
          .DEPTH_WIDTH  (AWIDTH),
          .DATA_WIDTH   (DWIDTH)
          ) u_fifo1
     (
      .clk        (CLK),
      .rst        (~RESETn),
      .wr_data_i  (c1_wrdata),
      .wr_en_i    (c1_wren),
      .rd_data_o  (c1_rddata),
      .rd_en_i    (c1_rden),
      .full_o     (c1_wrfull),
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
      .wr_data_i  (c2_wrdata),
      .wr_en_i    (c2_wren),
      .rd_data_o  (c2_rddata),
      .rd_en_i    (c2_rden),
      .full_o     (c2_wrfull),
      .empty_o    (c2_rdempty)
      );

   // Internal logic
   logic                          data_valid;
   logic [FIFO_PAYLOAD_WIDTH-1:0] dcnt;
   wire                           sel;
   logic                          psel;
   wire [DWIDTH-1:0]              cmd;
   logic [DWIDTH-1:0]             pcmd;
   
   // Mostly combinatorial logic
   assign fifo_rden = ~fifo_rdempty & ~c1_wrfull & ~c2_wrfull;
   assign c1_wrdata = fifo_rddata;
   assign c2_wrdata = fifo_rddata;
   assign sel = (dcnt != 0) ? psel :
                ((cmd & SELMASK) != 0 ? 1 : 0);
   assign c1_wren = data_valid & sel  ? 1'b1 : 1'b0;
   assign c2_wren = data_valid & !sel ? 1'b1 : 1'b0;
   assign cmd = (dcnt == 0) & data_valid ? fifo_rddata : pcmd;
   
   always @(posedge CLK)
     begin
        if (~RESETn)
          begin
             data_valid <= 0;
             dcnt       <= 0;
             pcmd       <= 0;
             psel       <= 0;
          end
        else 
          begin

             // Decode count field
             if (data_valid && (dcnt == 0))
               dcnt <= fifo_payload (FIFO_CNT_WIDTH'((32'(cmd) >> CSHIFT) & CMASK));
                   
             // data_valid lags by one cycle
             if (fifo_rden)
               data_valid <= 1;
             else
               data_valid <= 0;

             // Decrement if data valid
             if (data_valid & (dcnt != 0))
                 dcnt <= dcnt - 1;

             // Save to prevent feedback
             pcmd <= cmd;
             psel <= sel;

          end
     end
endmodule // fifo_arb_rx
