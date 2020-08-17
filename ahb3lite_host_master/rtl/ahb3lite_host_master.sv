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
                             WAIT,     // Wait one cycle
                             DATA      // DATA phase
                             } state_t;

   // Local buffer sizes
   localparam IWIDTH = 64;
   localparam OWIDTH = 32;
   
   // Buffer for command and data
   logic [31:0]                   addr;   // Save address for autoincrement
   logic [7:0]                    cmd;    // Command to execute
   logic [FIFO_PAYLOAD_WIDTH-1:0] icnt;   // Data in count
   logic [$clog2(OWIDTH/8):0]     ocnt;   // Data out count
   logic [IWIDTH-1:0]             dati;   // Data in
   logic [OWIDTH-1:0]             dato;   // Data out
   logic                          dvalid; // Is fifo data valid
   wire                           busy;   // Suppress incoming data when needed
   wire                           block;  // Block incoming while outgoing saturated
   state_t                        state;  // State machine
   
   // Assign busy signal
   assign busy = ((icnt == 0) & dvalid) | (state != IDLE);
   
   // Block while outgoing saturated
   assign block = WRFULL | (WREN & (ocnt != 0));

   // Always read when not busy and data is available
   assign RDEN = ~busy & ~RDEMPTY & !block;

   // Write when data is available and not full
   assign WREN = (ocnt != 0) & !WRFULL;

   
   always @(posedge CLK)
     if (!RESETn)
       begin
          dvalid <= 0;
          cmd <= 0;
          icnt <= 0;
          ocnt <= 0;
          state <= IDLE;
          HTRANS <= HTRANS_IDLE;
          addr <= 0;
          dati <= 0;
          dato <= 0;
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
          if (WREN & (ocnt != 0))
            begin
               ocnt <= ocnt - 1;
               WRDATA <= dato[7:0];
               dato <= {8'h0, dato[OWIDTH-1:8]};
            end
          
          // State machine
          case (state)
            IDLE:
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

                        // If zero byte command we must switch states here
                        if (RDDATA[6:4] == 0)
                          state <= ADDR;
                        
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
                        casez (cmd[1:0])
                          2'b00: begin HADDR <= dati[39:8];  addr <= dati[39:8];  end
                          2'b01: begin HADDR <= dati[47:16]; addr <= dati[47:16]; end
                          2'b1?: begin HADDR <= dati[63:32]; addr <= dati[63:32]; end
                        endcase
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
                 state <= WAIT;
              end // case: ADDR

            //
            // Wait for transaction to latch
            WAIT:
              begin
                 // Put data on bus regardless of slave HREADY
                 // NOTE: We only support aligned access
                 if (HWRITE)
                   // Replicate across lanes
                   casez (cmd[1:0])
                     2'b00: HWDATA <= {dati[7:0], dati[7:0], dati[7:0], dati[7:0]};
                     2'b01: HWDATA <= {dati[15:0], dati[15:0]};
                     2'b1?: HWDATA <= dati[31:0];
                   endcase

                 // Change bus state to IDLE
                 HTRANS <= HTRANS_IDLE;
                 state <= DATA;
              end
            
            //
            // DATA state
            //
            DATA:
              begin
                 
                 // Once client is ready check for error
                 // Save data is no error
                 if (HREADY)
                   begin
                      
                      // Check for error
                      if (HRESP == HRESP_ERROR)
                        begin
                           // Respond with error
                           WRDATA <= {cmd[7], FIFO_D0, 3'h0, 1'b1};
                           ocnt <= 1;
                        end
                      // Read data from bus, send to host
                      else if (~HWRITE)
                        begin
                           casez (cmd[1:0])
                             2'b00: begin 
                                dato <= {HRDATA[31:0] >> (HADDR[1:0] * 8)};
                                WRDATA <= {cmd[7], FIFO_D1, 4'h0};
                                ocnt <= 2; 
                             end
                             2'b01: begin
                                if (HADDR[1])
                                  dato <= {16'h0, HRDATA[23:16], HRDATA[31:24]};
                                else
                                  dato <= {16'h0, HRDATA[7:0], HRDATA[15:8]};
                                WRDATA <= {cmd[7], FIFO_D2, 4'h0};
                                ocnt <= 3; 
                             end
                             2'b1?: begin
                                dato <= {HRDATA[7:0], HRDATA[15:8], HRDATA[23:16], HRDATA[31:24]};
                                WRDATA <= {cmd[7], FIFO_D4, 4'h0};
                                ocnt <= 5; 
                             end
                           endcase // casez (cmd[1:0])
                        end
                      else
                        begin
                           // Successful write, return success
                           WRDATA <= {cmd[7], FIFO_D0, 4'h0};
                           ocnt <= 1;
                        end
 
                      // Move to response state
                      state <= IDLE;
                   end
              end // case: DATA
            default: state <= IDLE;
              
          endcase // case (state)
       end /* !RESETn */
   
endmodule // ahb3lite_host_master
