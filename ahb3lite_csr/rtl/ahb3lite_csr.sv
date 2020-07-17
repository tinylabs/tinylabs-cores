/**
 *  Configurable AHB3 CSR slave
 * 
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */

module ahb3lite_csr 
  #(
    parameter CNT = 2
    ) (
       // Global inputs
       input                         CLK,
       input                         RESETn,
       
       // AHB interface
       input                         HSEL,
       input [31:0]                  HADDR,
       input [31:0]                  HWDATA,
       input                         HWRITE,
       input [ 2:0]                  HSIZE,
       input [ 2:0]                  HBURST,
       input [ 3:0]                  HPROT,
       input [ 1:0]                  HTRANS,
       input                         HREADY,
       output logic [31:0]           HRDATA,
       output logic                  HREADYOUT,
       output logic                  HRESP,

       // Registers
       input [CNT-1:0] [1:0]         ACCESS,
       input [CNT-1:0] [31:0]        REGIN,
       output logic [CNT-1:0] [31:0] REGOUT
    );

   // AHB3 defs
   import ahb3lite_pkg::*;

   // Internal signals
   logic                    we;  // Write enable
   logic [3:0]              be;  // Byte enable
   logic [CNT-1:0]          sel; // Register select
   
   // No wait states for this core
   assign HREADYOUT = 1'b1;
   assign HRESP     = HRESP_OKAY;
   assign sel       = HADDR[CNT+1:2];

   // Generate byte enable
   assign be = (HSIZE == HSIZE_WORD) ? 4'hf :
               ((HSIZE == HSIZE_HWORD) ? (4'h3 << HADDR[1:0]) :
                4'h1 << HADDR[1:0]
                );

   // Generate new write value
   function logic [31:0] wval;
      input [31:0]          oval, nval;
      input [3:0]           be;
      for (int n=0; n < 4; n++)
        wval[n*8 +: 8] = be[n] ? nval[n*8 +: 8] : oval[n*8 +: 8];
   endfunction : wval
                                             
   // Generate internal write signal
   always @(posedge CLK)
     if (HREADY)
       we <= HSEL & HWRITE & (HTRANS != HTRANS_BUSY) & (HTRANS != HTRANS_IDLE);
     else
       we <= 1'b0;

   always @(posedge CLK)
     begin

        if (~RESETn)
          begin
             // Initialize with REGIN on reset
             for (int n = 0; n < CNT; n++)
               REGOUT[n] <= REGIN[n];
          end
        // Only operate when RESET is not asserted
        else
          begin

             // Switch on access mode
             case (ACCESS[sel])
               2'b00: begin // RW
                  if (we &  (sel < CNT))
                    REGOUT[sel] <= wval (REGOUT[sel], HWDATA, be);
                  else
                    HRDATA <= (sel < CNT) ? REGIN[sel] : 32'hdeadbeef;
               end
               2'b01: begin // RO
                  HRDATA <= (sel < CNT) ? REGIN[sel] : 32'hdeadbeef;
               end
               2'b10: begin // WO
                  if (we &  (sel < CNT))
                    REGOUT[sel] <= wval (REGOUT[sel], HWDATA, be);                  
                  else
                    HRDATA <= (sel < CNT) ? 32'h0 : 32'hdeadbeef;
               end
               2'b11: begin // W1C
                  if (we &  (sel < CNT))
                    REGOUT[sel] <= REGOUT[sel] & wval (REGOUT[sel], ~HWDATA, be);
                  else
                    HRDATA <= (sel < CNT) ? REGIN[sel] : 32'hdeadbeef;                  
               end
             endcase // case (ACCESS[sel])
             
          end // if (RESETn)
     end // always @ (posedge CLK)
   


endmodule // ahb3lite_csr

