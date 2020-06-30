/**
 * Connects to one AHB master and one AHB slave. Muxes traffic to and from the host via FIFO. 
 * Multiple bytewise transport protocols can be supported on the other side of the FIFO
 * 
 * All rights reserved.
 * Tiny Labs Inc
 * 2019-2020
 */
module ahb3lite_host_bridge (
                 /* Master clock */
                 input               CLK,
                 /* Reset signal */
                 input               RESETn,
                 /* AHB master interface */
                 output logic        mst_HWRITE, 
                 output logic [1:0]  mst_HTRANS, 
                 output logic [2:0]  mst_HSIZE,
                 output logic [31:0] mst_HADDR, 
                 output logic [2:0]  mst_HBURST, 
                 output logic [3:0]  mst_HPROT, 
                 output logic [31:0] mst_HWDATA,
                 input               mst_HREADY, 
                 input [31:0]        mst_HRDATA, 
                 input               mst_HRESP,
                 /* AHB slave interface */
                 input               slv_HREADY,
                 input               slv_HWRITE, 
                 input               slv_HSEL,
                 input [1:0]         slv_HTRANS, 
                 input [2:0]         slv_HSIZE, 
                 input [31:0]        slv_HADDR,
                 input [2:0]         slv_HBURST, 
                 input [3:0]         slv_HPROT,
                 input [31:0]        slv_HWDATA, 
                 output logic        slv_HREADYOUT,
                 output logic [31:0] slv_HRDATA, 
                 output logic        slv_HRESP, 
                 /* Connection to FIFO */
                 output logic        fifo_rden,
                 input               fifo_rdempty,
                 output logic        fifo_wren,
                 input               fifo_wrfull,
                 input [7:0]         fifo_rddata,
                 output logic [7:0]  fifo_wrdata
                 );
   
   // Borrow constants
   import ahb3lite_pkg::*;
   
   // Host interface
   logic                         host_rdfifo;

   // Double buffer the host data in
   logic [1:0] [7:0]             host_cmd;
   logic [1:0] [63:0]            host_dati;
   logic [1:0] [3:0]             host_cnti;
   logic                         host_idi;

   // Double buffer target data out
   logic [1:0] [71:0]            host_dato;
   logic [1:0] [3:0]             host_cnto;
   logic                         host_ido;

   // AHB master variables
   logic [31:0]                  mst_addr;
   logic [31:0]                  mst_dat;
   logic [1:0]                   mst_size;
   logic                         mst_write;
   
   // AHB master state machine
   typedef enum                  logic [1:0] {
                                              MST_IDLE,
                                              MST_ADDR_PHASE,
                                              MST_DATA_PHASE,
                                              MST_RESPONSE
                                               } master_state_t;
   master_state_t mst_state;

   // AHB slave state machine
   typedef enum                  logic [1:0] { 
                                               SLV_ADDRCYC,
                                               SLV_DATACYC,
                                               SLV_BUSY,
                                               SLV_WAITLATCH
                                               } slave_state_t;
   slave_state_t slv_state;
   
// Uncomment to enable loopback
//`define FT245_LOOPBACK 1

// DEBUG - loopback test
`ifdef FT245_LOOPBACK
   always @(posedge CLK)
     begin
        if (!RESETn)
          begin
             fifo_wren <= 0;
             fifo_rden <= 0;
          end
             
        else if (!fifo_rdempty)
          begin
             fifo_rden <= 1;
          end
        else if (fifo_rden)
          begin
             fifo_wrdata <= fifo_rddata;
             fifo_wren <= 1;
	     fifo_rden <= 0;
          end
        else if (fifo_wren)
          begin
             fifo_wren <= 0;
          end
     end // always @ (posedge CLK)
`else

   // Read always enabled
   assign fifo_rden = 1;

   /*
    * Receive a command/data over FT245 interface
    */
   always @(posedge CLK)
     begin
        // Reset all logic when asserted
        if (!RESETn)
          begin

             // Host input pipeline
             host_cmd <= 0;
             host_dati <= 0;
             host_cnti <= 0;
             host_idi <= 0;
             // Output pipeline
             host_dato <= 0;
             host_cnto <= 0;
             host_ido <= 0;
             host_rdfifo <= 0;

             // Master AHB interface
             mst_state <= MST_IDLE;
             slv_state <= SLV_ADDRCYC;

             // Make sure master is IDLE
             mst_HTRANS <= HTRANS_IDLE;

             // Slave AHB interface
             slv_HREADYOUT <= 1;
          end

        //
        // HOST to TARGET pipeline - Double buffered
        //
        
        // After rdempty asserts trigger read next cycle
        if (!fifo_rdempty)
          host_rdfifo <= 1;
        else
          host_rdfifo <= 0;

        // If data available and read enabled read into current buffer
        if (host_rdfifo & fifo_rden)
          begin

             // If count it zero then read command
             if (host_cnti[host_idi] == 0)
               begin

                  // Save command
                  host_cmd[host_idi] <= fifo_rddata;

                  // Decode expected following bytes
                  casez (fifo_rddata)
                    8'b0000_????: host_cnti[host_idi] <= 0;                         // Reserved
                    8'b0001_0000: host_cnti[host_idi] <= 1;                         // Slave resp (success byte read)
                    8'b0001_0001: host_cnti[host_idi] <= 2;                         // Slave resp (success hwrd read)
                    8'b0001_0010: host_cnti[host_idi] <= 4;                         // Slave resp (success word read)
                    8'b0001_0011: begin
                       host_cnti[host_idi] <= 0;
                       host_idi <= ~host_idi;
                    end                                                             // Slave resp (write success)
                    8'b0001_01??: begin 
                       host_cnti[host_idi] <= 0;
                       host_idi <= ~host_idi;
                    end                                                             // Slave resp (transaction failed)
                    8'b0001_1???: host_cnti[host_idi] <= 0;                         // Reserved
                    8'b0010_0???: host_cnti[host_idi] <= 4;                         // Master read
                    8'b0010_1???: begin
                       host_cnti[host_idi] <= 0;
                       host_idi <= ~host_idi;
                    end                                                               // Master read autoincrement
                    8'b0011_0???: host_cnti[host_idi] <= 4 + (1 << fifo_rddata[1:0]); // Master write
                    8'b0011_1???: host_cnti[host_idi] <= (1 << fifo_rddata[1:0]);     // Master write autoincrement
                    8'b1???_????: host_cnti[host_idi] <= 4;                           // Reserved
                    8'b01??_????: host_cnti[host_idi] <= 4;                           // Reserved
                  endcase
               end // if (!host_cnti[host_idi])
             else
               begin
                  // Shift in data, decrement cnt
                  host_dati[host_idi] <= {host_dati[host_idi][55:0], fifo_rddata};
                  host_cnti[host_idi] <= host_cnti[host_idi] - 1;

                  // Flip double buffer when done
                  if (host_cnti[host_idi] == 1)
                    host_idi <= ~host_idi;
               end
          end

        //
        // PROCESS command - We operate on the opposite index as the input stage
        //
        if ((host_cmd[!host_idi] != 0) && (host_cnti[!host_idi] == 0))
          begin

             // Switch on command
             casez (host_cmd[!host_idi][7:3])

               //
               // Master AHB access
               //
               // Master read
               5'b0010_0:
                 begin
                    mst_HADDR  <= host_dati[!host_idi][31:0];
                    mst_HWRITE <= 0;
                    mst_HBURST <= 0;
                    mst_HPROT  <= 4'b0011;
                    mst_HSIZE  <= {1'b0, host_cmd[!host_idi][1:0]};
                    mst_HTRANS <= HTRANS_NONSEQ;
                    mst_state  <= MST_ADDR_PHASE;
                    mst_write  <= 0;
                    mst_addr   <= host_dati[!host_idi][31:0];
                    mst_size   <= host_cmd[!host_idi][1:0];
                 end
               // Master read autoincrement
               5'b0010_1:
                 begin
                    mst_HADDR  <= mst_addr + (1 << host_cmd[!host_idi][1:0]);
                    mst_HWRITE <= 0;
                    mst_HBURST <= 0;
                    mst_HPROT  <= 4'b0011;
                    mst_HSIZE  <= {1'b0, host_cmd[!host_idi][1:0]};
                    mst_HTRANS <= HTRANS_NONSEQ;
                    mst_state  <= MST_ADDR_PHASE;
                    mst_write  <= 0;
                    mst_addr   <= mst_addr + (1 << host_cmd[!host_idi][1:0]);
                    mst_size   <= host_cmd[!host_idi][1:0];
                 end
               // Master write
               5'b0011_0:
                 begin
                    mst_HADDR  <= host_dati[!host_idi][31:0];
                    mst_HWRITE <= 1;
                    mst_HBURST <= 0;
                    mst_HPROT  <= 4'b0011;
                    mst_HSIZE  <= {1'b0, host_cmd[!host_idi][1:0]};
                    mst_HTRANS <= HTRANS_NONSEQ;
                    mst_HWDATA <= host_dati[!host_idi][63:32] << (8 * host_dati[!host_idi][1:0]);
                    mst_state  <= MST_ADDR_PHASE;
                    mst_write  <= 1;
                    mst_addr   <= host_dati[!host_idi][31:0];
                    mst_size   <= host_cmd[!host_idi][1:0];
                 end
               // Master write autoincrement
               5'b0011_1:
                 begin
                    mst_HADDR  <= mst_addr + (1 << host_cmd[!host_idi][1:0]);
                    mst_HWRITE <= 1;
                    mst_HBURST <= 0;
                    mst_HPROT  <= 4'b0011;
                    mst_HSIZE  <= {1'b0, host_cmd[!host_idi][1:0]};
                    mst_HTRANS <= HTRANS_NONSEQ;
                    mst_HWDATA <= host_dati[!host_idi][31:0] << (8 * mst_addr[1:0]);
                    mst_state  <= MST_ADDR_PHASE;
                    mst_write  <= 1;
                    mst_addr   <= mst_addr + (1 << host_cmd[!host_idi][1:0]);
                    mst_size   <= host_cmd[!host_idi][1:0];
                 end // case: 5'b0011_1
               
               // Slave response
               5'b0001_0:
                 begin
                    // Deassert hreadyout
                    slv_HREADYOUT <= 1;

                    // If returning data latch onto bus
                    if (host_cmd[!host_idi][1:0] != 2'b11)
                      slv_HRDATA <= host_dati[!host_idi][31:0];

                    // Return status code
                    slv_HRESP <= host_cmd[!host_idi][2];

                    // Move back to waiting for transaction
                    slv_state <= SLV_WAITLATCH;
                 end
               default:
                 ;/* Reserved */
             endcase // casex (host_cmd[!host_idi][7:3])

             // Clear command
             host_cmd[!host_idi] <= 0;
          end

        //
        // AHB master state machine
        //
        
        // Maintain address phase until hready goes high
        if ((mst_state == MST_ADDR_PHASE) && mst_HREADY)
          begin
             // Move to data phase
             mst_state <= MST_DATA_PHASE;
          end

        // In data phase
        if (mst_state == MST_DATA_PHASE)
          begin
             // If write then get data from bus
             if (!mst_write)
               mst_dat <= mst_HRDATA >> (8 * mst_HADDR[1:0]);
             
             // Wait for slave to acknowledge
             if (mst_HREADY)
               begin
                  // Transaction accepted move to ADDRCYC
                  mst_state <= MST_RESPONSE;
                  mst_HTRANS <= HTRANS_IDLE;
               end
          end

        if (mst_state == MST_RESPONSE)
          begin

             // Return write status
             if (mst_write)
               begin
                  host_dato[host_ido] <= {{64{1'b0}}, 5'h2, mst_HRESP, 2'b11};
                  host_cnto[host_ido] <= 1;
               end
             // Return read data + status
             else
               begin
                  casez (mst_size)
                    2'b1?: host_dato[host_ido] <= {{32{1'b0}}, mst_dat[7:0], mst_dat[15:8], mst_dat[23:16], 
                                                   mst_dat[31:24], 5'h2, mst_HRESP, mst_size};
                    2'b01: host_dato[host_ido] <= {{48{1'b0}}, mst_dat[7:0], mst_dat[15:8], 5'h2, mst_HRESP, mst_size};
                    2'b00: host_dato[host_ido] <= {{56{1'b0}}, mst_dat[7:0], 5'h2, mst_HRESP, mst_size};
                  endcase
                  host_cnto[host_ido] <= 1 + (1 << mst_size);
               end

             // Flip buffer
             host_ido <= ~host_ido;
            
             // Return to address state
             mst_state <= MST_IDLE;
          end
        
        //
        // TARGET to HOST pipeline - Double buffered
        //
        if ((host_cnto[!host_ido] != 0) && !fifo_wrfull)
          begin
             // Shift out data
             fifo_wrdata <= host_dato[!host_ido][7:0];
             host_cnto[!host_ido] <= host_cnto[!host_ido] - 1;
             host_dato[!host_ido] <= {8'h0, host_dato[!host_ido][71:8]};
             fifo_wren <= 1;             
          end
        else
          fifo_wren <= 0;

        //
        // SLAVE AHB input stage
        //
        if (slv_HSEL & slv_HREADY &&
            (slv_state == SLV_ADDRCYC) &&
            (slv_HTRANS != HTRANS_BUSY) &&
            (slv_HTRANS != HTRANS_IDLE))
          begin
             
             // Assert busy
             slv_HREADYOUT <= 0;

             // Handle reads
             if (!slv_HWRITE)
               begin

                  // Send command to host
                  host_dato[host_ido] <= {{32{1'b0}}, slv_HADDR[7:0], slv_HADDR[15:8],
                                          slv_HADDR[23:16], slv_HADDR[31:24], 6'h9, slv_HSIZE[1:0]};
                  host_cnto[host_ido] <= 5;
                  host_ido <= ~host_ido;
                  slv_state <= SLV_BUSY;
                  
               end // if (!slv_HWRITE)
             
             // Must delay one cycle to latch write data
             else
               begin
                  // Latch address and operation
                  host_dato[host_ido] <= {{32{1'b0}}, slv_HADDR[7:0], slv_HADDR[15:8],
                                          slv_HADDR[23:16], slv_HADDR[31:24], 6'hd, slv_HSIZE[1:0]};

                  // Move to state to latch data
                  slv_state <= SLV_DATACYC;
               end
          end // if (slv_HSEL & slv_HREADY &...

        //
        // SLAVE AHB data cycle
        //
        if (slv_state == SLV_DATACYC)
          begin

             // Latch in data
             host_dato[host_ido] <= {slv_HWDATA[7:0], slv_HWDATA[15:8], slv_HWDATA[23:16], slv_HWDATA[31:24],
                                     host_dato[host_ido][39:0]};
             host_cnto[host_ido] <= 9;
             host_ido <= ~host_ido;
             slv_state <= SLV_BUSY;
          end

        // Wait for master to latch
        if (slv_state == SLV_WAITLATCH)
          begin
             slv_state <= SLV_ADDRCYC;
          end
        
     end // always @ (posedge CLK or negedge RESETn)
`endif // !FT245_LOOPBACK
endmodule // host_mux

   
