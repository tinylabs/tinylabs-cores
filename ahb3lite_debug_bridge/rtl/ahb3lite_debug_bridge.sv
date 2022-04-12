/**
 * Transparent bridge between AHB3 slave and ADIv5 ARM debug interface
 * 
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2022
 */

import adiv5_pkg::*;
import ahb3lite_pkg::*;

module ahb3lite_debug_bridge 
   (
    // Core signals
    input                              CLK,
    input                              RESETn,

    // Route to default slave when not enabled
    input                              ENABLE,

    // Side channel stat if failure
    output logic [2:0]                 STAT,
    
    // Transparent AHB slave bridge
    input                              HREADY,
    input                              HWRITE,
    input                              HSEL,
    input [1:0]                        HTRANS,
    input [2:0]                        HSIZE,
    input [31:0]                       HADDR,
    input [2:0]                        HBURST,
    input [3:0]                        HPROT,
    input [31:0]                       HWDATA,
    output logic                       HREADYOUT,
    output logic [31:0]                HRDATA,
    output logic                       HRESP,

    // ADIv5 FIFO interface
    output logic [ADIv5_CMD_WIDTH-1:0] ADIv5_WRDATA,
    output logic                       ADIv5_WREN,
    input                              ADIv5_WRFULL,
    input [ADIv5_RESP_WIDTH-1:0]       ADIv5_RDDATA,
    output logic                       ADIv5_RDEN,
    input                              ADIv5_RDEMPTY
   );

   // Default slave when bridge is disabled, mux outputs
   logic [31:0]                 dslv_HRDATA, slv_HRDATA;
   logic                        dslv_HREADYOUT, slv_HREADYOUT;
   logic                        dslv_HRESP, slv_HRESP;
   assign HRDATA    = ENABLE ? slv_HRDATA    : dslv_HRDATA;
   assign HRESP     = ENABLE ? slv_HRESP     : dslv_HRESP;
   assign HREADYOUT = ENABLE ? slv_HREADYOUT : dslv_HREADYOUT;

   // Always returns error - without bus will hang
   ahb3lite_default_slave
     u_default_slave (
                      .CLK        (CLK),
                      .RESETn     (RESETn),
                      .HSEL       (HSEL & ~ENABLE),
                      .HTRANS     (HTRANS),
                      .HREADY     (HREADY),
                      .HREADYOUT  (dslv_HREADYOUT),
                      .HRESP      (dslv_HRESP),
                      .HRDATA     (dslv_HRDATA)
                      );
   
   // State machine
   typedef enum logic [4:0] {
                             STATE_DISABLED,        // 0: Interface disabled
                             STATE_IDLE,            // 1: Waiting for command
                             STATE_CACHE_DPSELECT,  // 2: 2-6 are caching 
                             STATE_READ_DPSELECT,   // 3: DPSELECT and APCSW
                             STATE_WRITE_DPSELECT,  // 4: during enable.
                             STATE_CACHE_APCSW,     // 5:
                             STATE_READ_APCSW,      // 6:
                             STATE_ACCESS_DRW,      // 7: Read/Write DRW
                             STATE_ACCESS_BDn,      // 8: Read/Write BD[0-3]
                             STATE_SELECT_APBANK_0, // 9:
                             STATE_SELECT_APBANK_1, // 10:
                             STATE_SET_CSW,         // 11:
                             STATE_SET_TAR,         // 12:
                             STATE_AHB_RESP,        // 13:
                             STATE_AHB_ERROR_WAIT   // 14:
                             } brg_state_t;
   brg_state_t state;
 
   // AHB interface
   logic [31:0]        ahb_tar;        // Cache of tar value
   logic [31:0]        ahb_addr;       // AHB address to access
   logic [31:0]        ahb_data;       // data to read/write
   logic               ahb_wnr;        // Write=1 Read=0
   logic [3:0]         ahb_bd;         // Banked data reg 0/4/8/c
   logic               ahb_pending;    // AHB transaction pending
   logic               ahb_latch_data; // Latch data next cycle
   logic [2:0]         ahb_req_sz;     // Requested size

   // Track commands pending/received
   logic [2:0]         resp_pending;
   logic [2:0]         resp_recvd;
   logic               cmd_complete;
              
   // Save response from last cmd
   adiv5_resp resp;
   
   // Registers
   adiv5_ap_csw        csw;
   adiv5_dp_sel        sel;
   logic [31:0]        tar;

   // Command is complete when we've received all responses
   assign cmd_complete = (resp_pending == resp_recvd);
 
   // Always read responses while available
   assign ADIv5_RDEN = !ADIv5_RDEMPTY;
   
   // Remote AHB bridge
   always @(posedge CLK)
     begin
        if (!ENABLE)
          state <= STATE_DISABLED;

        // Main processing
        else
          begin

             // Latch data
             if (ADIv5_RDEN)
               begin
                  resp <= ADIv5_RDDATA;
                  check_resp <= 1;
                  resp_recvd++;
               end

             // Check response just latched in
             if (check_resp)
               begin
                  // Stop checking if we're done
                  if (!ADIv5_RDEN)
                    check_resp <= 0;

                  // Set sticky STAT reg if failure
                  if (resp.stat != STAT_OK)
                       STAT <= resp.stat;
               end
              
             // Latch ahb data next cycle
             if (ahb_latch_data)
               begin
                  //$display ("sz=%d addr=%h data=%h", ahb_req_sz, ahb_addr, HWDATA);
                  ahb_data <= HWDATA;
                  ahb_latch_data <= 0;
               end                    

             // State machine
             case (state)

               STATE_DISABLED:
                 begin

                    // Once enabled cache DP_SEL and AP_CSW
                    if (ENABLE)
                      state <= STATE_CACHE_DPSELECT;
                    else
                      begin
                         // Reset all variables
                         ahb_tar <= -1;
                         ahb_addr <= -1;
                         ahb_pending <= 0;
                         ahb_latch_data <= 0;
                         resp_pending <= 0;
                         resp_recvd <= 0;
                         check_resp <= 0;
                         slv_HREADYOUT <= 1;
                         STAT <= STAT_OK;
                         ADIv5_WREN <= 0;
                      end
                 end

               STATE_IDLE:
                 begin

                    // No current error
                    slv_HRESP <= HRESP_OKAY;

                    // Complete AHB transaction
                    if (ahb_pending)
                      begin

                         // Clear pending
                         ahb_pending <= 0;
                       
                         // Determine how to most efficiently handle the request
                         // This is actually a somewhat complicated decision tree.
                         // NOTE: This causes a wait state which is necessary for
                         // the case where we are writing directly to DRW. AHB
                         // data will latch in parallel to this state.

                         // If size mismatch handle that first
                         if (ahb_req_sz != csw.width)
                           begin
                              if (bank_match (AP_ADDR_CSW))
                                state <= STATE_SET_CSW;
                              else
                                state <= STATE_SELECT_APBANK_0;
                           end
                         // If TAR exact match and width is correct then access DRW
                         else if (ahb_addr == tar)
                           begin
                              if (bank_match (AP_ADDR_DRW))
                                state <= STATE_ACCESS_DRW;
                              else
                                state <= STATE_SELECT_APBANK_0;
                           end
                         // BDn not consistent with autoinc or non-word width
                         else if ((ahb_req_sz != CSW_WIDTH_WORD) || (csw.autoinc == CSW_INC_SINGLE) || (ahb_addr[31:2] != tar[31:2]))
                           begin
                              // Check if bank matches TAR/CSW bank
                              if (bank_match (AP_ADDR_TAR))
                                begin
                                   if (ahb_req_sz != csw.width)
                                     state <= STATE_SET_CSW;
                                   else
                                     state <= STATE_SET_TAR;
                                end
                              else
                                state <= STATE_SELECT_APBANK_0;
                           end
                         // Banked access possible
                         // If we get here:
                         // width = WORD
                         // banked access within TAR
                         // Auto-increment is OFF
                         else
                           begin
                              // Check apbank match
                              if (bank_match (AP_ADDR_BD0))
                                state <= STATE_ACCESS_Bn;
                              else
                                state <= STATE_SELECT_APBANK_1;
                           end
                      end
                 end // case: STATE_IDLE

               // Cache DP_SELECT
               STATE_CACHE_DPSELECT:
                 if (!ADIv5_WRFULL)
                   begin
                      ADIv5_WRDATA <= DP_REG_READ (DP_ADDR_SELECT);
                      ADIv5_WREN <= 1;
                      cmd_pending++;
                      state <= STATE_READ_DPSELECT;
                   end
                 else
                   ADIv5_WREN <= 0;

               // Save DP-SEL, inherit configured values
               STATE_READ_DPSELECT:
                 begin
                    ADIv5_WREN <= 0;                    
                    if (cmd_complete)
                      begin
                         // Save select register
                         sel <= resp.data;
                         state <= STATE_WRITE_DPSELECT;
                      end
                 end
               
               // Write DP Select
               STATE_WRITE_DPSELECT:
                 if (!ADIv5_WRFULL)
                   begin
                      // Note: We don't change APSEL. That's inherited
                      // from configuration before enabling bridge
                      //                       
                      // Clear dpbank - We don't use it for bridge
                      sel.dpbank = 0;
                      // Set apbank for CSW read
                      sel.apbank = 0;
                      // Send READ_AP command
                      ADIv5_WRDATA <= DP_REG_WRITE (DP_ADDR_SELECT);
                      ADIv5_WREN <= 1;
                      cmd_pending++;
                      state <= STATE_CACHE_APCSW;
                   end
                 else
                   ADIv5_WREN <= 0;

               // Cache AP_CSW
               STATE_CACHE_APCSW:
                 if (!ADIv5_WRFULL)
                   begin
                      // Send READ_AP command
                      ADIv5_WRDATA <= AP_REG_READ (AP_ADDR_CSW);
                      ADIv5_WREN <= 1;
                      cmd_pending++;
                      state <= STATE_READ_APCSW;
                   end
                 else
                   ADIv5_WREN <= 0;

               // Save CSW reg - inherit configured values
               STATE_READ_APCSW:
                 begin
                    ADIv5_WREN <= 0;
                    if (cmd_complete)
                      begin
                         // Save CSW
                         csw <= resp.data;
                         // Put into IDLE
                         state <= STATE_IDLE;
                      end
                 end
               
               // Access DRW directly
               STATE_ACCESS_DRW:
                 if (!ADIv5_WRFULL)
                   begin
                      // Directly access DRW
                      ADIv5_WREN <= 1;
                      cmd_pending++;
                      if (ahb_wnr)
                        begin
                           ADIv5_WRDATA <= AP_REG_WRITE (AP_ADDR_DRW, ahb_data);
                           // Increment TAR if enabled
                           if (csw.autoinc == CSW_INC_SINGLE)
                             tar <= tar + (1 << csw.width);
                        end
                      else
                        ADIv5_WRDATA <= AP_REG_READ (AP_ADDR_DRW);
                      state <= STATE_AHB_RESP;
                   end
                 else
                   ADIv5_WREN <= 0;

               // Access banked BDn register
               STATE_ACCESS_BDn:
                 if (!ADIv5_WRFULL)
                   begin
                      ADIv5_WREN <= 1;
                      cmd_pending++;
                      if (ahb_wnr)
                        ADIv5_WRDATA <= AP_REG_WRITE (AP_ADDR_BD0 | ahb_addr[1:0], ahb_data);
                      else
                        ADIv5_WRDATA <= AP_REG_READ (AP_ADDR_BD0 | ahb_addr[1:0]);
                      state <= STATE_AHB_RESP;
                   end
                 else
                   ADIv5_WREN <= 0;
               
               // Switch to apbank 0
               STATE_SELECT_APBANK_0:
                 if (!ADIv5_WRFULL)
                   begin
                      sel.apbank = 0;
                      ADIv5_WRDATA <= DP_REG_WRITE (DP_ADDR_SELECT, sel);
                      ADIv5_WREN <= 1;
                      cmd_pending++;

                      // If access size doesn't match set CSW
                      if (csw.width != ahb_req_sz)
                        state <= STATE_SET_CSW;
                      else if (ahb_addr == tar)
                        state <= STATE_ACCESS_DRW;
                      // Otherwise set TAR
                      else
                        state <= STATE_SET_TAR;
                   end
                 else
                   ADIv5_WREN <= 0;
               
               // Switch to apbank 1
               STATE_SELECT_APBANK_1:
                 if (!ADIv5_WRFULL)
                   begin
                      sel.apbank = 1;
                      ADIv5_WRDATA <= DP_REG_WRITE (DP_ADDR_SELECT, sel);
                      ADIv5_WREN <= 1;
                      cmd_pending++;

                      // Access Bn banked register
                      state <= STATE_ACCESS_Bn;
                   end
                 else
                   ADIv5_WREN <= 0;
               
               // Set CSW width
               STATE_SET_CSW:
                 if (!ADIv5_WRFULL)
                   begin
                      csw.width = ahb_req_sz;
                      ADIv5_WRDATA <= AP_REG_WRITE (AP_ADDR_CSW, csw);
                      ADIv5_WREN <= 1;
                      cmd_pending++;
                      // If TAR already matches
                      if (ahb_addr == tar)
                        state <= STATE_ACCESS_DRW;
                      // else set TAR
                      else
                        state <= STATE_SET_TAR;
                   end
                 else
                   ADIv5_WREN <= 0;
                      
               // Set TAR address
               STATE_SET_TAR:
                 if (!ADIv5_WRFULL)
                   begin
                      tar = ahb_addr;
                      ADIv5_WRDATA <= AP_REG_WRITE (AP_ADDR_TAR, tar);
                      ADIv5_WREN <= 1;
                      cmd_pending++;
                      state <= STATE_ACCESS_DRW;
                   end
                 else
                   ADIv5_WREN <= 0;
               
               // Return response to AHB master
               STATE_AHB_RESP:
                 begin
                    // Done issuing commands
                    ADIv5_WREN <= 0;

                    // Wait until all responses received
                    if (cmd_complete)
                      begin
                                        
                         // Clear pending/received
                         resp_pending <= 0;
                         resp_recvd <= 0;

                         // Latch read data onto AHB3 bus
                         if (!ahb_wnr)
                           slv_HRDATA <= resp.data;
                        
                         // Set response as OKAY/ERROR
                         if (STAT != STAT_OK)
                           begin
                              // Signal error
                              slv_HRESP <= HRESP_ERROR;

                              // Go to wait state for one cycle
                              state <= STATE_AHB_ERROR_WAIT;
                           end
                         else
                           begin
                              slv_HRESP <= HRESP_OKAY;

                              // De-assert HREADYOUT
                              slv_HREADYOUT <= 1;
                         
                              // Put back in IDLE state
                              state <= STATE_IDLE;
                           end
                      end
                 end // case: STATE_AHB_RESP
               
               // HRESP must be asserted for two cycles during an error
               STATE_AHB_ERROR_WAIT:
                 begin
                    slv_HREADYOUT <= 1;
                    state <= STATE_IDLE;
                 end

               // Should never get here
               default:
                 state <= STATE_DISABLED;
               
             endcase // case (state)

             // Handle AHB slave requests
             if (HSEL &
                 HREADY &&
                 (HTRANS != HTRANS_BUSY) &&
                 (HTRANS != HTRANS_IDLE))
               begin

                  // Set HREADYOUT as busy
                  slv_HREADYOUT <= 0;

                  // Latch addr
                  ahb_addr <= HADDR;
                                    
                  // Save read write state
                  ahb_wnr <= HWRITE;

                  // Save transaction size
                  ahb_req_sz <= {0, HSIZE[1:0]};
                       
                  // If write latch data next cycle
                  if (HWRITE)
                    ahb_latch_data <= 1;

                  // Process next IDLE cycle
                  ahb_pending <= 1;
                  
               end // if (HSEL &...
          end // else: !if(!RESETn)        
     end // always @ (posedge CLK)

endmodule // ahb3lite_remote_bridge


