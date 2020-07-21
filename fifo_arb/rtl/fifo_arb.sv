/**
 *  Bidirectional FIFO arbiter - Two unidirectional fifos connect to a common source/sink
 *  Two clients connected each have a receive and transmit fifo.
 * 
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */

module fifo_arb #(
                  parameter DW = 8,
                  parameter AW = 3,
                  parameter SELMASK = 8'h80,
                  parameter CNTMASK = 8'h70
                  )
   (
    // Global connections
    input           CLK,
    input           RESETn,

    // Common birectional FIFO
    output          com_rden,
    input           com_rdempty,
    input [DW-1:0]  com_rddata,
    output          com_wren,
    input           com_wrfull,
    output [DW-1:0] com_wrdata,
    
    // Client 1
    input           c1_rden,
    output          c1_rdempty,
    output [DW-1:0] c1_rddata,
    input           c1_wren,
    output          c1_wrfull,
    input [DW-1:0]  c1_wrdata,
          
    // Client 2
    input           c2_rden,
    output          c2_rdempty,
    output [DW-1:0] c2_rddata,
    input           c2_wren,
    output          c2_wrfull,
    input [DW-1:0]  c2_wrdata
    );

   // Instantiate RX arbiter
   fifo_arb_rx #(
                 .SELMASK  (SELMASK),
                 .CNTMASK  (CNTMASK),
                 .DWIDTH   (DW),
                 .AWIDTH   (AW))
   u_arb_rx (
             .CLK          (CLK),
             .RESETn       (RESETn),
             // Client 1
             .c1_rden      (c1_rden),
             .c1_rdempty   (c1_rdempty),
             .c1_rddata    (c1_rddata),             
             // Client 2
             .c2_rden      (c2_rden),
             .c2_rdempty   (c2_rdempty),
             .c2_rddata    (c2_rddata),
             // Common
             .fifo_rden    (com_rden),
             .fifo_rdempty (com_rdempty),
             .fifo_rddata  (com_rddata)
             );
   
   // Instantiate TX arbiter
   fifo_arb_tx #(
                 .SELMASK  (SELMASK),
                 .CNTMASK  (CNTMASK),
                 .DWIDTH   (DW),
                 .AWIDTH   (AW))
   u_arb_tx (
             .CLK          (CLK),
             .RESETn       (RESETn),
             // Client 1
             .c1_wren      (c1_wren),
             .c1_wrfull    (c1_wrfull),
             .c1_wrdata    (c1_wrdata),             
             // Client 2
             .c2_wren      (c2_wren),
             .c2_wrfull    (c2_wrfull),
             .c2_wrdata    (c2_wrdata),
             // Common
             .fifo_wren    (com_wren),
             .fifo_wrfull  (com_wrfull),
             .fifo_wrdata  (com_wrdata)
             );
   
endmodule // fifo_arb
