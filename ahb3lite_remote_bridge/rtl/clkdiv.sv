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
   input [4:0]  DIV,
   output logic CLKOUT
   );

   logic [4:0]  ctr;

   // CLKOUT DIVISOR
   // 0 = DIV2
   // 1 = DIV4
   // 2 = DIV6
   // 3 = DIV8
   // 4 = DIV10
   // 5 = DIV12
   // 6 = DIV14
   // 7 = DIV16
   // 8 = DIV18
   // 9 = DIV20
   // 10 = DIV22
   // 11 = DIV24
   // 12 = DIV26
   // 13 = DIV28
   // 14 = DIV30
   // 15 = DIV32
   // 16 = DIV34
   // 17 = DIV36
   // 18 = DIV38
   // 19 = DIV40
   // 20 = DIV42
   // 21 = DIV44
   // 22 = DIV46
   // 23 = DIV48
   // 24 = DIV50
   // 25 = DIV52
   // 26 = DIV54
   // 27 = DIV56
   // 28 = DIV58
   // 29 = DIV60
   // 30 = DIV61
   // 31 = DIV62
   always @(posedge CLKIN)
     begin
        if (!RESETn)
          begin
             ctr <= 0;
             CLKOUT <= 0;
          end
        else
          begin
             
             // Flip
             if (ctr == DIV)
               begin
                  CLKOUT <= ~CLKOUT;
                  ctr <= 0;
               end
             else
               // Increment counter
               ctr <= ctr + 1;
          end
     end
endmodule // clkdiv
