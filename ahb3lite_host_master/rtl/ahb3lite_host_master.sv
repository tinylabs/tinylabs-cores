/**
 *  ahb3lite_host_master connects a host PC to the AHB3 bus as a master. This 
 *  allows initiating transactions on the bus, reading/writing memory, etc.
 * 
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2019-2020
 */

module ahb3lite_host_master
  (
   /* Global connections */
   input               CLK,
   input               RESETn,
   /* Host FIFO interface */
   output              RDEN,
   input               RDEMPTY,
   output logic        WREN,
   input               WRFULL,
   input [7:0]         RDDATA,
   output logic [7:0]  WRDATA,
   /* AHB3 master */
   output logic        HWRITE,
   output logic [1:0]  HTRANS,
   output logic [2:0]  HSIZE,
   output logic [31:0] HADDR,
   output logic [2:0]  HBURST,
   output logic [3:0]  HPROT,
   output logic [31:0] HWDATA,
   input               HREADY,
   input [31:0]        HRDATA,
   input               HRESP
   );

   // Import AHB3 constants
   import ahb3lite_pkg::*;

   // Import fifo constants
   import host_fifo_pkg::*;
   
   // Simple AHB master state machine
   typedef enum logic [1:0] {
                             IDLE = 0, // Waiting for cmd
                             ADDR,     // ADDR phase
                             DATA      // DATA phase
                             } state_t;

   // Local buffer sizes
   localparam IWIDTH = 64;
   localparam OWIDTH = 40;
   
   // Buffer for command and data
   logic [7:0]                    cmd;    // Command to execute
   logic [$clog2(IWIDTH/8)-1:0]   icnt;   // Data in count
   logic [$clog2(OWIDTH/8)-1:0]   ocnt;   // Data out count
   logic [IWIDTH-1:0]             dati;   // Data in
   logic [OWIDTH-1:0]             dato;   // Data out
   logic                          dvalid; // Is fifo data valid
   wire                           busy;   // Suppress incoming data when needed
   state_t                        state;  // State machine
   
   // Assign busy signal
   assign busy = ((icnt == 0) & dvalid) | (state != IDLE);
   
   // Always read when not busy and data is available
   assign RDEN = ~busy & ~RDEMPTY;
   
   always @(posedge CLK)
     if (!RESETn)
       begin
          dvalid <= 0;
          busy <= 0;
          cmd <= 0;
          icnt <= 0;
          state <= IDLE;
          HTRANS <= HTRANS_IDLE;
       end
     else
       begin

          // Data valid next cycle after read
          if (RDEN)
            dvalid <= 1;
          else
            dvalid <= 0;

          // 
          // Outgoing DATA TO HOST
          //
          if ((ocnt != 0) & ~WRFULL)
            begin
               WREN <= 1;
               WRDATA <= dato[7:0];
               dato <= {8'h0, dato[OWIDTH-1:8]};
               ocnt <= ocnt - 1;
            end
          
          //
          // INCOMING DATA FROM HOST FIFO
          //
          if (dvalid)
            begin

               // First byte is command
               if (icnt == 0)
                 begin
                    // Save command
                    cmd <= RDDATA;

                    // Decode payload count
                    icnt <= fifo_payload (RDDATA[6:4]);

                    // If zero byte command added must move state here...
                 end
               // Following icnt data is all payload
               else
                 begin
                    // Shift in payload, decrement icnt
                    dati <= {dati[IWIDTH-8-1:0], RDDATA};
                    icnt <= icnt - 1;

                    // All data is in make state
                    if (icnt == 1)
                      state <= ADDR;                    
                 end
            end // if (dvalid)

          // State machine
          case (state)
            //
            // PROCESS HOST COMMAND
            //
            ADDR:
              begin

                 // Decode command: ABBBCDEE
                 // 
                 // A=interface (0/1) - ignore
                 // BBB=data size
                 // C=Read (0)/Write (1)
                 // D=autoincrement (Autoincrement previously accessed address)
                 // EE=transfer size
                 //   00=byte
                 //   01=hwrd
                 //   10=word
                 //
                 case (cmd[3:2])
                   2'b00: /* Read no autoincrement */
                     begin
                        HWRITE <= 0;
                        HADDR  <= dati[31:0];
                        addr   <= dati[31:0];
                     end
                   2'b01: /* Read w/ autoincrement*/
                     begin
                        HWRITE <= 0;
                        HADDR  <= addr + (1 << cmd[1:0]);
                        addr   <= addr + (1 << cmd[1:0]);
                     end
                   2'b10: /* Write no autoincrement */
                     begin
                        HWRITE <= 1;
                        HADDR  <= data[63:32];
                        addr   <= dati[63:32];
                     end
                   2'b11: /* Write w/ autoincrement*/
                     begin
                        HWRITE <= 1;
                        HADDR  <= addr + (1 << cmd[1:0]);
                        addr   <= addr + (1 << cmd[1:0]);
                     end
                 endcase // casez (cmd[3:0])
                 
                 // Common bus signals
                 HBURST <= 0;
                 HPROT  <= 4'h3;
                 HTRANS <= HTRANS_NONSEQ;
                 HSIZE  <= {1'b0, cmd[1:0]};
                 
                 // Move to data state
                 state <= DATA;
              end // case: ADDR

            //
            // DATA state
            //
            DATA:
              begin
                 // Put data on bus regardless of slave HREADY
                 // NOTE: We only support aligned access
                 if (HWRITE)
                   // Put on correct byte lanes
                   casez (cmd[1:0])
                     2'b00: HWDATA <= data[7:0]  << (8 * HADDR[1:0]);
                     2'b01: HWDATA <= data[15:0] << (8 * {HADDR[1], 1'b0});
                     2'b1?: HWDATA <= data[31:0];
                   endcase
                 
                 // Once client is ready check for error
                 // Save data is no error
                 if (HREADY)
                   begin
                      // Change bus state to IDLE
                      HTRANS <= HTRANS_IDLE;
                      
                      // Check for error
                      if (HRESP == HRESP_ERROR)
                        begin
                           // Respond with error
                           dato <= {cmd[7], FIFO_D0, 3'h0, 1'b1};
                           cnto <= 1;
                        end
                      // Read data from bus, send to host
                      else if (~HWRITE)
                        casez (cmd[1:0])
                          2'b01: begin dato <= {HRDATA[7:0],  {cmd[7], FIFO_D1, 4'h0}}; cnto <= 2; end
                          2'b10: begin dato <= {HRDATA[15:0], {cmd[7], FIFO_D2, 4'h0}}; cnto <= 3; end
                          2'b1?: begin dato <= {HRDATA[31:0], {cmd[7], FIFO_D4, 4'h0}}; cnto <= 5; end
                        endcase // casez (cmd[1:0])
                      else
                        begin
                           // Successful write, return success
                           dato <= {cmd[7], FIFO_D0, 4'h0};
                           cnto <= 1;
                        end
 
                      // Move to response state
                      state <= IDLE;
                   end
              end // case: DATA
          endcase // case (state)
       end /* !RESETn */
   
endmodule // ahb3lite_host_master
