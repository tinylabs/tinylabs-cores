/**
 *  SWD (serial wire debug) physical interface
 * 
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */

module swd_phy
  (
   // Core signals
   input               CLK,
   input               RESETn,
   
   // Hardware interface
   input               SWDCLKIN,
   output logic        SWDCLKOUT,
   input               SWDIN,
   output logic        SWDOUT,
   output logic        SWDOE,

   // Shift register interface
   input [5:0]         T0,
   input [5:0]         T1,
   input [63:0]        SO,
   output logic [35:0] SI,
   input [5:0]         LEN,
   // Ready/done flags
   input               VALID,
   output logic        READY,
   output logic [2:0]  ERR
   );

   // Error conditions
   typedef enum logic [2:0] {
                             SUCCESS,           // 000
                             ERR_FAULT,         // 001
                             ERR_WAIT,          // 010
                             ERR_NOCONNECT,     // 011
                             ERR_UNKNOWN = 7    // 111
                             } err_t;
   
   // Internal logic
   logic [5:0]  ctr;
   logic [5:0]  len;
   logic [5:0]  t0;
   logic [5:0]  t1;
   logic [63:0] so;
   logic        check;
   logic        pclk;


   // Synchronize slower clock using fast clock
   logic        qSWDCLKIN;
   sync2_pgen clk_sync (.c (CLK), .d (SWDCLKIN), .p (), .q (qSWDCLKIN));
     
   // Set flag when we need to check status response
   assign check = ((t0 == 8) && (ctr == 12) && !SWDCLKOUT) ? 1'b1 : 1'b0;
   
   always @(posedge CLK)
     begin
        // Reset locals if in reset
        if (!RESETn)
          begin
             pclk   <= 0;
             ctr    <= 0;
             len    <= 0;
             t0     <= 0;
             t1     <= 0;             
             SWDOE  <= 0;
             SWDOUT <= 0;
             READY  <= 1;
          end
        else
          begin
             
             // Save previous clock
             pclk <= qSWDCLKIN;
             
             // Check for error conditions
             if (check)
               begin
                  case (SI[2:0])
                    3'b001:  ERR <= ERR_FAULT;
                    3'b010:  ERR <= ERR_WAIT;
                    3'b100:  ERR <= SUCCESS;
                    3'b111:  ERR <= ERR_NOCONNECT;
                    default: ERR <= ERR_UNKNOWN;
                  endcase // casex (SI[2:0])
                  
                  // Start driving if this was a read
                  if ((SI[2:0] != 3'b100) && (t1 > 12))
                    begin
                       SWDOE <= 1;
                       t1 <= 0;
                       so <= {64{1'b0}};
                    end
               end // if (check)
             
             //
             // RISING edge
             //
             if (!pclk  & qSWDCLKIN)
               begin
                  if (ctr < len)
                    SWDCLKOUT <= 1;
               end // RISING edge
             
             //
             // FALLING edge
             //
             if (pclk & !qSWDCLKIN)
               begin

                  // Accept new transactions
                  if (VALID)
                    begin
                       ctr   <= 0;
                       len   <= LEN;
                       so    <= SO;
                       t0    <= T0;
                       t1    <= T1;
                       READY <= 0;
                       ERR   <= 0;
                       SI    <= 0;
                    end
                  
                  // Shift when in transaction
                  if (ctr < len)
                    begin
                       
                       // Switch direction when counter matches
                       if ((ctr == t0) || (ctr == t1))
                         SWDOE <= ~SWDOE;
                       // Else shift in
                       else if (!SWDOE)
                         SI <= {SI[34:0], SWDIN};
                       
                       // Write when SWDOE enabled
                       if (SWDOE)
                         begin
                            SWDOUT <= so[0];
                            so <= {1'b0, so[63:1]};
                         end
                       
                       // Increment counter
                       ctr <= ctr + 1;

                       // Set ready when done
                       if (ctr == (len - 1))
                         READY <= 1;

                       // Drive output clock
                       SWDCLKOUT <= 0;
                       
                    end // if (ctr < len)
                  
               end // FALLING edge
             
          end // else: !if(!RESETn)
     end // always @ (posedge CLK)
   
endmodule // swd_phy

