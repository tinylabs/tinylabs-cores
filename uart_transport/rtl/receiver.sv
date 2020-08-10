/**
 *  UART receiver - Non-configurable. Uses autobaud for divider detection.
 * 
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */
module receiver
  # (CPB_WIDTH = 12)
  (
   input                        CLK,
   (* mark_debug = "true" *) input RESETn,
   // Data pin
   input                        RX_PIN,
   // Clocks per bit for Tx,
   output logic [CPB_WIDTH-1:0] CPB,
   // FIFO interface on output
   (* mark_debug = "true" *) output logic [7:0] WRDATA,
   (* mark_debug = "true" *) output logic WREN,
   (* mark_debug = "true" *) input WRFULL,
   // Error count
   output logic [9:0]           ERR
   );

   // Oversample rate
   localparam OVERSAMPLE = 4;

   // Majority rules function
   function logic majority;
      input [OVERSAMPLE-1:0]         in;
      logic [$clog2(OVERSAMPLE):0]   cnt = 0;

      // Count bits
      for (int i = 0; i < OVERSAMPLE; i++)
        if (in[i])
          cnt = cnt + 1;
      //$display ("%04b : cnt=%d", in, cnt);      
      majority = (32'(cnt) >= OVERSAMPLE / 2) ? 1'b1 : 1'b0;
   endfunction // majority

   // Receive state machine
   typedef enum logic [1:0] {
                             AUTOBAUD,
                             IDLE,
                             DATA
                             } state_t;
   
   (* mark_debug = "true" *) state_t      state;  // State machine
   logic        pb;     // Previous bit
   (* mark_debug = "true" *) logic [3:0]  bcnt;   // Bit count
   logic [CPB_WIDTH-1:0] acc;    // Accumulator
   logic [CPB_WIDTH-1:0] ctr;    // Internal counter for baud generation
   logic [OVERSAMPLE-2:0] sample; // Sample count
   (* mark_debug = "true" *) logic [$clog2(OVERSAMPLE):0] ocnt;   // Oversample count
   logic [8:0]           data;   // Sampled data
   
   
   always @(posedge CLK)
     begin

        // Track previous bit
        pb <= RX_PIN;

        if (!RESETn)
          begin
             CPB <= 0;
             bcnt <= 0;
             acc <= 0;
             ctr <= 0;
             state <= AUTOBAUD;
             WREN <= 0;
             ERR <= 0;
          end
        else
          begin
                          
             // Receive state machine
             case (state)
               AUTOBAUD:
                 begin
                    
                    // Look for transitions
                    if (pb ^ RX_PIN)
                      begin
                         bcnt <= bcnt + 1;
                         acc <= 0;
                         if (bcnt != 0)
                           CPB <= (CPB == 0) ? CPB_WIDTH'(acc) + 1 : (CPB + acc + 1) / 2;
                      end
                    else
                      acc <= acc + 1;

                    // Autobaud done
                    if (bcnt == 10)
                      begin
                         state <= IDLE;
                         acc <= CPB >> $clog2 (OVERSAMPLE);
                         // Pass on sync byte
                         // This is necessary for consistency between initial reset
                         // and non-reset states
                         WRDATA <= 8'h55;
                         WREN <= 1;
                      end                 
                 end // case: AUTOBAUD
               
               IDLE: // Look for start bit and transition
                 begin
                    WREN <= 0;
                    ocnt <= 1; // First bit sampled already
                    bcnt <= 0;
                    data <= 0;
                    sample <= 0;
                    if (acc - 1 > 0)
                      ctr <= 1;
                    else
                      ctr <= 0;

                    // Change state when RX pin goes low
                    if (!RX_PIN)
                      begin
                         state <= DATA;
                      end
                 end // case: IDLE
               
               DATA: 
                 begin

                    // Increment counter
                    if (ctr >= acc - 1)
                      ctr <= 0;
                    else
                      ctr <= ctr + 1;

                    // Check if bit time complete
                    if (ctr == 0)
                      begin
                         // Sample data
                         sample <= {sample[OVERSAMPLE-3:0], RX_PIN};
                         ocnt <= ocnt + 1;

                         // Check if bit time is complete
                         if (32'(ocnt) == OVERSAMPLE - 1)
                           begin
                              // Byte finished
                              if (bcnt == 9)
                                begin
                                   
                                   // Check for START/STOP bit errors
                                   if ((majority ({sample, RX_PIN}) == 0) ||
                                       (data[0] == 1))
                                     begin
                                        ERR <= ERR + 1;
                                        state <= IDLE;
                                     end
                                   else
                                     begin
                                        WRDATA <= data[8:1];
                                        WREN <= 1;
                                        state <= IDLE;
                                     end
                                end
                              else
                                begin
                                   ocnt <= 0;
                                   data <= {majority ({sample, RX_PIN}), data[8:1]};
                                   bcnt <= bcnt + 1;
                                end
                           end // if (32'(ocnt) == OVERSAMPLE - 1)
                      end // if (ctr == 0)

                 end // case: DATA
               
               default: state <= IDLE; // Should never get here...              
            
             endcase // case (state)       
          end // else: !if(~RESETn)   
     end // always @ (posedge CLK)
   
endmodule // receiver

