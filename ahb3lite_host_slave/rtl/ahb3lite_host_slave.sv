/**
 *  ahb3lite_host_slave connects a host PC to the AHB3 slave. This 
 *  allows host to respond to transactions as if they were on the bus
 * 
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2019-2020
 */

module ahb3lite_host_slave
  // Set to 1 if using interface 1 with FIFO arbiter
  // Shouldn't need to change this
  #(parameter IBIT = 1'b0)
   (
    /* Global connections */
    input               CLK,
    input               RESETn,
    // When set to 0 slave will respond using default slave
    input               EN,
    /* Host FIFO interface */
    output logic        RDEN,
    input               RDEMPTY,
    output logic        WREN,
    input               WRFULL,
    input [7:0]         RDDATA,
    output logic [7:0]  WRDATA,
    /* AHB3 slave */
    input               HREADY,
    input               HWRITE,
    input               HSEL,
    input [1:0]         HTRANS,
    input [2:0]         HSIZE,
    input [31:0]        HADDR,
    input [2:0]         HBURST,
    input [3:0]         HPROT,
    input [31:0]        HWDATA,
    output logic [31:0] HRDATA,
    output logic        HRESP,
    output logic        HREADYOUT
   );

   // Import AHB3 constants
   import ahb3lite_pkg::*;

   // Import host fifo defs
   import host_fifo_pkg::*;
   
   // Simple AHB master state machine
   typedef enum logic [2:0] {
                             IDLE = 0, // Waiting for cmd
                             WAITDATA, // Wait for data phase
                             WAITRESP, // Wait for host response
                             AHBRESP,  // Send AHB response
                             ERRDELAY  // Delay one cycle for error case
                             } state_t;

   // Local buffer sizes
   localparam IWIDTH = 40;
   localparam OWIDTH = 72;
   
   // Buffer for command and data
   logic [$clog2(IWIDTH/8)-1:0]   icnt;   // Data in count
   logic [$clog2(OWIDTH/8)-1:0]   ocnt;   // Data out count
   logic [IWIDTH-1:0]             dati;   // Data in
   logic [OWIDTH-1:0]             dato;   // Data out
   logic                          dvalid; // Is fifo data valid
   state_t                        state;  // State machine
   wire                           err;
   wire [31:0]                    sdat;   // Adjusted data based on address
   logic [1:0]                    size;   // HSIZE for current transaction
   logic                          write;  // HWRITE for current transaction
   logic [31:0]                   addr;   // HADDR
   
   // Point to correct response bit for error
   assign err = write ? dati[0] :
                ((size[1:0] == 2'b00) ? dati[8] :
                 ((size[1:0] == 2'b01) ? dati[16] : dati[32]));
   
   // Always read when not busy and data is expected
   assign RDEN = ~RDEMPTY && (icnt != 0);

   // Shift data based on address
   assign sdat = HWDATA >> (8 * addr[1:0]);
     
   //
   // When host slave is not enabled use default slave to return error
   //
   ahb3lite_default_slave
     u_default_slave (
                      .CLK        (CLK),
                      .RESETn     (RESETn),
                      .HSEL       (HSEL & ~EN),
                      .HTRANS     (HTRANS),
                      .HREADY     (HREADY),
                      .HREADYOUT  (HREADYOUT),
                      .HRESP      (HRESP),
                      .HRDATA     (HRDATA)
                      );
   
   always @(posedge CLK)
     if (!RESETn)
       begin
          dati <= 0;
          dato <= 0;
          dvalid <= 0;
          icnt <= 0;
          ocnt <= 0;
          state <= IDLE;
          //HRESP <= HRESP_OKAY; handled by default slave
          //HREADYOUT <= 1;
       end
     else if (EN)
       begin

          // Data valid trails by one clock
          if (RDEN)
            dvalid <= 1;
          else
            dvalid <= 0;

          // Pass outgoing data to host
          if ((ocnt != 0) & ~WRFULL)
            begin
               WREN <= 1;
               WRDATA <= dato[7:0];
               dato <= {8'h0, dato[OWIDTH-1:8]};
               ocnt <= ocnt - 1;               
            end
          else
            WREN <= 0;
          
          // Slave state machine
          case (state)
            IDLE:
              begin

                 // Return no error
                 HRESP <= HRESP_OKAY;
                 
                 // Respond to bus transactions
                 if (HSEL & HREADY &&
                     (HTRANS != HTRANS_BUSY) &&
                     (HTRANS != HTRANS_IDLE))
                   begin
                      
                      // Assert busy immediately - we know this will take many cycles
                      HREADYOUT <= 0;
                      size <= HSIZE[1:0];
                      write <= HWRITE;
                      addr <= HADDR;
                      
                      // Send read to host
                      if (~HWRITE)
                        begin
                           // Send read to host
                           dato <= {32'h0, 
                                    HADDR[7:0], HADDR[15:8], HADDR[23:16], HADDR[31:24],
                                    IBIT, FIFO_D4, HWRITE, 1'b0, HSIZE[1:0]};
                           ocnt <= 5;

                           // Calc exprected response len
                           // 1 byte resp + (1,2,4) bytes data
                           casez (HSIZE[1:0])
                             2'b00: icnt <= 2;
                             2'b01: icnt <= 3;
                             2'b1?: icnt <= 5;
                           endcase

                           // Wait for host response
                           state <= WAITRESP;
                        end
                      // For write wait one cycle for data
                      else
                        state <= WAITDATA;
                   end
              end // case: IDLE

            // Wait for data from master
            // This should always come one cycle after ADDR phase
            WAITDATA:
              begin
                 casez (size[1:0])
                   2'b00: // byte access
                     begin
                        dato <= {24'h0, sdat[7:0], 
                                 addr[7:0], addr[15:8], addr[23:16], addr[31:24],
                                 IBIT, FIFO_D5, write, 1'b0, size[1:0]};
                        ocnt <= 6;
                     end
                   2'b01: // hwrd access
                     begin
                        dato <= {16'h0, sdat[7:0], sdat[15:8], 
                                 addr[7:0], addr[15:8], addr[23:16], addr[31:24],
                                 IBIT, FIFO_D6, write, 1'b0, size[1:0]};
                        ocnt <= 7;
                     end
                   2'b1?: // word access
                     begin
                        dato <= {sdat[7:0], sdat[15:8], sdat[23:16], sdat[31:24],
                                 addr[7:0], addr[15:8], addr[23:16], addr[31:24],
                                 IBIT, FIFO_D8, write, 1'b0, size[1:0]};
                        ocnt <= 9;
                     end
                 endcase

                 // wait for response from host
                 state <= WAITRESP;
                 
                 // Expected single write response from host
                 icnt <= 1; 
              end // case: WAITDATA

            //
            // Wait for host response
            WAITRESP:
              begin
                 if (dvalid)
                   begin
                      dati <= {dati[IWIDTH-8-1:0], RDDATA};
                      if (icnt == 1)
                        state <= AHBRESP;
                      if (icnt != 0)
                        icnt <= icnt - 1;
                   end
              end

            //
            // Send AHB response to master
            AHBRESP:
              begin

                 // If error extend one more cycle
                 if (err)
                   begin
                      HRESP <= HRESP_ERROR;
                      state <= ERRDELAY;
                   end
                 else
                   begin

                      // If read then move to bus
                      if (~write)
                        casez (size[1:0])
                          2'b00: HRDATA <= {dati[7:0], dati[7:0], dati[7:0], dati[7:0]};
                          2'b01: HRDATA <= {dati[15:0], dati[15:0]};
                          2'b1?: HRDATA <= dati[31:0];
                        endcase // casez (size[1:0])
                      
                      // Write OKAY
                      HRESP <= HRESP_OKAY;
                      
                      // Deassert HREADYOUT
                      HREADYOUT <= 1;

                      // Back to IDLE
                      state <= IDLE;
                   end
              end

            //
            // Clean up after error
            ERRDELAY:
              begin

                 HREADYOUT <= 1;
                 state <= IDLE;
              end

            // Just to be safe
            default:
              state <= IDLE;
            
          endcase // case (state)          
       end // if (EN)

endmodule // ahb3lite_host_slave
