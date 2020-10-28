/**
 *  CLK divisor for PHY
 * 
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */

module debug_clkdiv
  (
   input        CLKIN,
   input        RESETn,
   input [3:0]  SEL,
   output logic CLKOUT
   );

   logic [8:0]  ctr;

`define FLIP(v) begin if (ctr == v) begin CLKOUT <= ~CLKOUT; ctr <= 0; end else ctr <= ctr + 1; end
   
   // SEL  FREQ    DIVISOR
   // 0  = 192 MHz    1
   // 1  = 96 MHz     2
   // 2  = 64 MHz     3
   // 3  = 48 MHz     4
   // 4  = 32 MHz     6
   // 5  = 24 MHz     8
   // 6  = 19.2 MHz   10
   // 7  = 16 MHz     12
   // 8  = 12 MHz     16
   // 9  = 8 MHz      24
   // 10 = 6 MHz      32
   // 11 = 4 MHz      48
   // 12 = 3 MHz      64
   // 13 = 2 MHz      96
   // 14 = 1 MHz      192
   // 15 = 500 kHz    384
   always @(posedge CLKIN or negedge CLKIN)
     begin
        case (SEL)
          4'd0:  `FLIP (1)
          4'd1:  `FLIP (2)
          4'd2:  `FLIP (3)
          4'd3:  `FLIP (4)
          4'd4:  `FLIP (6)
          4'd5:  `FLIP (8)
          4'd6:  `FLIP (10)
          4'd7:  `FLIP (12)
          4'd8:  `FLIP (16)
          4'd9:  `FLIP (24)
          4'd10: `FLIP (32)
          4'd11: `FLIP (48)
          4'd12: `FLIP (64)
          4'd13: `FLIP (96)
          4'd14: `FLIP (192)
          4'd15: `FLIP (384)
        endcase
     end
endmodule // debug_clkdiv

