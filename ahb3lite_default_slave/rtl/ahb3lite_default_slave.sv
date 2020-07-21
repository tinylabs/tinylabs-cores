/**
 *  AHB3lite default slave - Handle non-matching requests and return ERROR.
 * 
 *  Tiny Labs Inc
 *  2020
 */

module ahb3lite_default_slave 
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

   logic               active;
               
/* Simple state machine - just return error according to AHB3 spec */
always @(posedge CLK)
  begin
     if (!RESETn)
       begin
          HREADYOUT <= 1;
          HRESP <= HRESP_OKAY;
          HRDATA <= 32'h0;
          active <= 0;
       end
     else
       begin
          if (HREADY & HSEL && (HTRANS != HTRANS_BUSY) && (HTRANS != HTRANS_IDLE))
            begin
               HREADYOUT <= 0;
               active <= 1;
            end
          else if (active)
            begin
               if (HRESP & HREADYOUT)
                 begin
                    HRESP <= 0;
                    active <= 0;
                 end
               else if (HRESP)
                 HREADYOUT <= 1;
               else if (!HREADYOUT)
                 HRESP <= 1;
            end
       end
  end   

endmodule // ahb3lite_dslave
