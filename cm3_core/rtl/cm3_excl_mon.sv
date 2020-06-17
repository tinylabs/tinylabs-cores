/**
 *  Cortex-M3 exclusive access monitor - If conditions are not met then prevent write and signal to processor.
 *  
 *  Tiny Labs Inc
 *  2019
 */

module cm3_excl_mon (
                     /* Clock */
                     CLK,
                     /* Reset */
                     RESETn,
                     /* Processor is halted - stop cycle count */
                     HALTED,
                     /* signal inputs */
                     HADDR, HWRITE, EXREQ,
                     /* signal outputs */
                     EXRESP, HWRITEOUT
                     );

   input         CLK;
   input         RESETn;
   input         HALTED;
   input [31:0]  HADDR;
   input         HWRITE;
   input         EXREQ;
   output logic  EXRESP;
   output        HWRITEOUT;
   
   // Allowable cycle delay between read and write in RMW ops
`define EXCL_DELAY 128
   
   // Store last excl read address
   logic [31:0]                      exaddr;
   logic [$clog2(`EXCL_DELAY)-1:0]   delay;
   logic                             valid;

   // HWRITEOUT = HWRITE unless !valid & EXREQ
   assign HWRITEOUT = ~valid & EXREQ ? 1'b0 : HWRITE;

   always @ (posedge CLK or negedge RESETn) begin
      if (~RESETn)
        begin
           EXRESP <= 1'b1;
           exaddr <= 32'h0;
           valid <= 1'b0;
        end
      else
        begin

           // Store addr and reset deley on EXCL_READ
           if (EXREQ & ~HWRITE)
             begin
                exaddr <= HADDR;
                delay <= 7'h7f;
                valid <= 1'b1;
             end

           // Ack exclusive accesses
           if (valid && (HADDR == exaddr))
             begin
                // ACK both read and write
                if (EXREQ)
                  EXRESP <= 1'b0;
                // If normal access then invalidate
                else
                  valid <= 1'b0;
                
                // Clear address if its a write
                if (HWRITE) 
                  begin
                     valid <= 1'b0;
                  end
             end
           else
             EXRESP <= 1'b1;

           // Count down if valid
           if (valid && ~HALTED)
             begin
                if (|delay)
                  delay <= delay - 1;
                else
                  begin
                     valid <= 1'b0;
                  end
             end           
        end // else: !if(~RESETn)
   end // always @ (posedge CLK)

endmodule // cm3_excl_mon
