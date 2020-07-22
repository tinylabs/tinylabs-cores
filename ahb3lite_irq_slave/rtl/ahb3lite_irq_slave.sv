/**
 *  Expose registers to generate IRQs. These registers are split between edge
 *  IRQs and level IRQs.
 * 
 *  uint32_t edge[IRQ_CNT/32];  // WO 
 *  uint32_t level[IRQ_CNT/32]; // RW 
 * 
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */

module ahb3lite_irq_slave
  #(
    parameter IRQ_CNT = 240
    ) (
       input                      CLK,
       input                      RESETn,
       // AHB interface
       input                      HSEL,
       input                      HWRITE,
       input                      HREADY,
       input [31:0]               HADDR,
       input [1:0]                HTRANS,
       input [2:0]                HSIZE,
       input [2:0]                HBURST,
       input [3:0]                HPROT,
       input [31:0]               HWDATA,
       output [31:0]              HRDATA,
       output                     HRESP,
       output                     HREADYOUT,
       // IRQ output
       output logic [IRQ_CNT-1:0] IRQ
       );

   // Autogen CSRs
   // With empty instance it will connect to default AHB3 interface signals
`include "irq_slave.vh"

   // Maintain IRQ
   for (genvar n = 0; n < IRQ_CNT / 32; n++)
     assign IRQ[n+31:n] = level_o | edge_o;

   // Maintain level over time
   assign level_i = level_o;
   assign edge_i = 32'h0;
   
endmodule // ahb3lite_irq_slave

     
