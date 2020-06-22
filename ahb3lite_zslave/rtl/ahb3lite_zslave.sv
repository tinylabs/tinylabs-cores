/**
 *  AHB3lite default slave - Handle non-matching requests and return ERROR.
 *  Note: It's named zslave bc the fusesoc gen framework sorts the clients alphabetically.
 * 
 *  Tiny Labs Inc
 *  2020
 */

module ahb3lite_zslave 
  (
   input               CLK,
   input               RESETn,
   // AHB3 interface (not all signals needed)
   input               HSEL,
   input [1:0]         HTRANS,
   input               HREADY,
   output logic        HREADYOUT,
   output logic        HRESP,
   output logic [31:0] HRDATA
   );

import ahb3lite_pkg::*;

/* Simple state machine - just return error according to AHB3 spec */
always @(posedge CLK)
  begin
     if (!RESETn)
       begin
          HREADYOUT <= 1;
          HRESP <= 0;
          HRDATA <= 32'h0;
       end
     else
       begin
          if (HREADY & HSEL && (HTRANS != HTRANS_BUSY) && (HTRANS != HTRANS_IDLE))
            HREADYOUT <= 0;
          else if (HRESP & HREADYOUT)
            HRESP <= 0;
          else if (HRESP)
            HREADYOUT <= 1;
          else if (!HREADYOUT)
            HRESP <= 1;
       end
  end   

endmodule // ahb3lite_dslave
