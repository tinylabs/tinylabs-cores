/**
 *  CLK divisor for JTAG/SWD
 * 
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */

module clkdiv
  (
   input        CLKIN,
   input        RESETn,
   input [2:0]  DIV,
   output logic CLKOUT
   );

   logic [7:0]  ctr;

   // Assign CLKOUT to tap
   // 0 = DIV2
   // 1 = DIV4
   // 2 = DIV8
   // 3 = DIV16
   // 4 = DIV32
   // 5 = DIV64
   // 6 = DIV128
   // 7 = DIV256
   assign CLKOUT = ctr[DIV];
   
   always @(posedge CLKIN)
     begin
        if (!RESETn)
          ctr <= 0;

        // Increment counter
        ctr <= ctr + 1;
     end
endmodule // clkdiv
