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

   // Calculate count shift
   localparam CWIDTH = 3; //$countbits (CNTMASK, '1); doesn't work
   localparam CSHIFT = $clog2 (CNTMASK) - CWIDTH;
   localparam CMASK  = (2**CWIDTH) - 1;
   
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
   logic                data_valid;
   logic [5:0]          dcnt;
   wire                 sel;
   wire [DWIDTH-1:0]    cmd;
   
   // Mostly combinatorial logic
   assign fifo_rden = ~fifo_rdempty;
   assign c1_wrdata = fifo_rddata;
   assign c2_wrdata = fifo_rddata;
   assign sel = (dcnt != 0) ? sel :
                ((cmd & SELMASK) != 0 ? 1 : 0);
   assign c1_wren = data_valid & sel  ? 1'b1 : 1'b0;
   assign c2_wren = data_valid & !sel ? 1'b1 : 1'b0;
   assign cmd = (dcnt == 0) ? fifo_rddata : cmd;
   
   always @(posedge CLK)
     begin
        if (~RESETn)
          begin
             data_valid <= 0;
             dcnt       <= 0;
          end
        else 
          begin

             // Decode count field
             if (data_valid && (cmd != 0))
               begin                  
                  case ((cmd >> CSHIFT) & CMASK)
                    CWIDTH'(0): dcnt <= 0;
                    CWIDTH'(1): dcnt <= 1;
                    CWIDTH'(2): dcnt <= 2;
                    CWIDTH'(3): dcnt <= 4;
                    CWIDTH'(4): dcnt <= 8;
                    default:    dcnt <= 0; // All other values reserved
                  endcase
               end
                   
             // data_valid lags by one cycle
             if (fifo_rden)
               begin
                  data_valid <= 1;
                  if (dcnt)
                    dcnt <= dcnt - 1;
               end
             else
               data_valid <= 0;
          end
     end
endmodule // fifo_arb_rx
