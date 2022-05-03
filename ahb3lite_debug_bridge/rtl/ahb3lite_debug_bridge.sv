/**
 * Transparent bridge between AHB3 slave and ADIv5 ARM debug interface
 * 
 *  IRQ scanning
 *    This consists of a target setup component (handled by software)
 *    and a hardware scanning component (implemented here). The setup
 *    must include the following:
 *    - Target runs minimal environment to push IRQs to 3 IRQ buffer
 *      at DCRDR. The format is the following:
 *    - CC XX YY ZZ where CC is the 8lsb of a 32bit counter
 *      and ZZ is the most recent IRQ.
 *    - IRQ is disabled after pushing to host.
 *    - Host reenables IRQ after servicing.
 * 
 *  Hardware scanning consists of the following when there are 
 *  spare cycles (No AHB3 request to service):
 *    - Continuously scan DCRDR for changes.
 *    - Calculate new IRQ count from 8lsb counter.
 *    - Push new IRQs to FIFO to forward to host.
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

    // Runtime control of sequential vs keyhole access.
    // Sequential access enables auto-increment for faster
    // access time but doesn't preclude the use of BDn.
    // Keyhole access disables auto-increment to allow
    // continuous access of 4 word bank using BDn.
    input                              SEQ,
    
    // Side channel stat if failure
    output logic [2:0]                 STAT,

    // Select AP - Required as DPv1+ does
    // not allow reading of DP-SELECT
    input [7:0]                        APSEL,

    // Scan for IRQs when IDLE
    // This requires target setups and
    // cooperation from the host
    input                              IRQSCAN,
    output logic [31:0]                IRQCNT,
    output logic [31:0]                IRQBASE,
    
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
    input                              ADIv5_RDEMPTY,

    // FIFO output for IRQ scanning
    output logic [7:0]                 IRQ_WRDATA,
    output logic                       IRQ_WREN,
    input                              IRQ_WRFULL,

    // FIFO input for IRQ ACK
    input logic [7:0]                  IRQ_RDDATA,
    input logic                        IRQ_RDEMPTY,
    output logic                       IRQ_RDEN
    );
   
   // Default slave when bridge is disabled, mux outputs
   logic [31:0]                        dslv_HRDATA, slv_HRDATA;
   logic                               dslv_HREADYOUT, slv_HREADYOUT;
   logic                               dslv_HRESP, slv_HRESP;
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
   parameter STATE_WIDTH = 5;
   typedef enum logic [STATE_WIDTH-1:0] {
                             STATE_DISABLED,              // 0: Interface disabled
                             STATE_IDLE,                  // 1: Waiting for command
                             STATE_WRITE_DPSELECT,        // 2: during enable.
                             STATE_CACHE_APCSW,           // 3:
                             STATE_READ_APCSW,            // 4:
                             STATE_ACCESS_DRW,            // 5: Read/Write DRW
                             STATE_ACCESS_BDn,            // 6: Read/Write BD[0-3]
                             STATE_SELECT_APBANK_0,       // 7:
                             STATE_SELECT_APBANK_1,       // 8:
                             STATE_SET_CSW,               // 9:
                             STATE_SET_TAR,               // 10:
                             STATE_AHB_RESP,              // 11:
                             STATE_AHB_ERROR_WAIT,        // 12:
                             STATE_UPDATE_APCSW,          // 13: Update for SEQ input
                             STATE_IRQSCAN,               // 14:
                             STATE_IRQSCAN_ACK,           // 15:
                             STATE_IRQSCAN_ERROR,         // 16:
                             STATE_COREREG_WRITE,         // 17: Not currently used but can expose
                             STATE_COREREG_ACCESS,        // 18: registers directly via CSR if
                             STATE_COREREG_POLL_DHCSR,    // 19: needed.
                             STATE_COREREG_READ_DCRDR,    // 20:
                             STATE_COREREG_DCRDR_LATCH    // 21:
                             } brg_state_t;
   brg_state_t state;
// Track state for debug
`ifndef SYNTHESIS
   brg_state_t pstate;
`endif

   // AHB interface
   logic [31:0]        ahb_addr;       // AHB address to access
   logic [31:0]        ahb_data;       // data to read/write
   logic               ahb_wnr;        // Write=1 Read=0
   logic [3:0]         ahb_bd;         // Banked data reg 0/4/8/c
   logic               ahb_pending;    // AHB transaction pending
   logic               ahb_latch_data; // Latch data next cycle
   logic [2:0]         ahb_req_sz;     // Requested size

   // Track commands pending/received
   parameter CTR_WIDTH = 3;
   logic [CTR_WIDTH-1:0] resp_pending;
   logic [CTR_WIDTH-1:0] resp_recvd;

   // General housekeeping
   logic                 cmd_complete;
   logic                 check_resp;
   logic                 init_complete;

   // Core register access API
   parameter CORE_REG_xPSR = 5'b10000;
   parameter CORE_REG_PC   = 5'b01111;

   typedef struct packed {
      logic [31:0]            data;
      logic [4:0]             sel;
      logic                   wnr;
      logic [STATE_WIDTH-1:0] next;
   } core_reg_t;

   // Global struct for core reg access
   core_reg_t core_reg;
   
   function core_reg_t CORE_REG_READ(logic [4:0] sel, logic [STATE_WIDTH-1:0] next);
      CORE_REG_READ.sel = sel;
      CORE_REG_READ.wnr = 0;
      CORE_REG_READ.next = next;
   endfunction // CORE_REG_READ

   function core_reg_t CORE_REG_WRITE(logic [4:0] sel, logic [31:0] data, logic [STATE_WIDTH-1:0] next);
      CORE_REG_WRITE.sel = sel;
      CORE_REG_WRITE.data = data;
      CORE_REG_WRITE.wnr = 1;
      CORE_REG_WRITE.next = next;
   endfunction // CORE_REG_WRITE
   
   // Save response from last cmd
   adiv5_resp_t resp;
   
   // DP/AP registers
   adiv5_ap_csw        csw;
   adiv5_dp_sel        sel;
   logic [31:0]        tar;

   // IRQ scan accounting
   logic               irq_scan_active;
   logic               irq_scan_error;
   logic               irq_processing;
   logic               irq_fifo_check_resp;
   logic               irq_cmd;
   logic               irq_scan_en;
   logic               irq_check_ack;
   logic [2:0]         irq_new_cnt;
   logic [31:0]        irq_prev;
   logic [31:0]        irq_ack;
   
   // IRQ fifo interface
   logic [31:0]        irq_fifo_wrdata, irq_fifo_rddata;
   logic               irq_fifo_wren, irq_fifo_rden;
   logic               irq_fifo_wrfull, irq_fifo_rdempty;
   
   // Instantiate an internal fifo for processing IRQs
   fifo #(
          .DEPTH_WIDTH  (3), // 8 slots in fifo
          .DATA_WIDTH   (32)
          ) u_irq_fifo
     (
      .clk        (CLK),
      .rst        (~RESETn),
      .wr_data_i  (irq_fifo_wrdata),
      .wr_en_i    (irq_fifo_wren),
      .rd_data_o  (irq_fifo_rddata),
      .rd_en_i    (irq_fifo_rden),
      .full_o     (irq_fifo_wrfull),
      .empty_o    (irq_fifo_rdempty)
      );   
   
   // Get max
   parameter CTR_MAX = CTR_WIDTH'($rtoi($pow (2, CTR_WIDTH) - 1));
   
   // Calculate previous response
   logic [CTR_WIDTH-1:0] resp_pending_next; //resp_pending_prev
   //assign resp_pending_prev = (resp_pending == 0) ? CTR_MAX : resp_pending - 1;
   assign resp_pending_next = (resp_pending == CTR_MAX) ? 0 : resp_pending + 1;
   
   // Synthesized inhibit signal
   // Inhibit if buffer is full or wrapping around
   logic               ADIv5_INHIBIT;
   assign ADIv5_INHIBIT = ADIv5_WRFULL | (resp_pending_next == resp_recvd);
   
   // Command is complete when we've received all responses
   assign cmd_complete = (resp_pending == resp_recvd);
 
   // Always read responses while available
   assign ADIv5_RDEN = !ADIv5_RDEMPTY;

   // Alway process IRQ FIFO when data is available
   assign irq_fifo_rden = !irq_fifo_rdempty & !irq_processing;

   // Read IRQ acks
   assign IRQ_RDEN = !IRQ_RDEMPTY;
   
   // Remote AHB bridge
   always @(posedge CLK)
     begin
        if (!ENABLE | !RESETn)
          begin
             state <= STATE_DISABLED;
             IRQCNT <= 0;
          end
        
        // Main processing
        else
          begin

             // Debug only
             `ifndef SYNTHESIS
             pstate <= state;
             if (state != pstate)
               $display ("%s", state.name);
             `endif

             // Check if scan becoming active
             if (!irq_scan_en & IRQSCAN)
               begin
                  // Here we co-opt the system to make
                  // the required request.
                  // BANKSEL->SET_TAR->READ BD0
                  ahb_req_sz <= CSW_WIDTH_WORD;
                  // IRQ base address
                  ahb_addr <= IRQBASE;
                  // Read operation
                  ahb_wnr <= 0;

                  // Clear irq variables
                  irq_prev <= 32'h0;
                  irq_ack <= 32'h0;
                  irq_check_ack <= 1;
               end // if (!irq_scan_en & IRQSCAN)

             // Lags one cycle
             irq_scan_en <= IRQSCAN;
             
             // Latch data
             if (ADIv5_RDEN)
               check_resp <= 1;

             // Check response just latched in
             if (check_resp)
               begin
                  // Stop checking if we're done
                  if (!ADIv5_RDEN)
                    check_resp <= 0;

                  // Get response
                  resp <= ADIv5_RDDATA;
                  resp_recvd <= resp_recvd + 1;
                  //$display ("state=%s resp=%h", state.name, ADIv5_RDDATA[ADIv5_RESP_WIDTH-1:3]);

                  // Set sticky STAT reg if failure
                  if (ADIv5_RDDATA[2:0] != STAT_OK)
                    begin
                       STAT <= ADIv5_RDDATA[2:0];
                       // Assume TAR is no longer valid if autoinc
                       // in case it was a failed write
                       tar <= -1;

                       // If there's an active scan then push error to interface
                       if (irq_scan_active)
                         begin
                            state <= STATE_IRQSCAN_ERROR;
                            IRQ_WRDATA <= 8'h01; // Write cmd to FIFO
                            IRQ_WREN <= 1;
                         end
                    end
               end // if (check_resp)

             // Latch incoming ACK
             if (IRQ_RDEN)
               irq_check_ack <= 1;

             // Handle incoming ACKs
             // Acks are single byte corresponding to position of IRQ
             if (irq_check_ack)
               begin
                  // Stop checking if we're done
                  if (!IRQ_RDEN)
                    irq_check_ack <= 0;

                  // OR in to current ack
                  irq_ack <= irq_ack | (32'hFF << (8 * IRQ_RDDATA[2:1]));
                  state <= STATE_IRQSCAN_ACK;
               end
             
             // Decode IRQs from internal FIFO
             if (irq_fifo_rden)
               begin
                  irq_fifo_check_resp <= 1;
                  irq_processing <= 1;
                  irq_cmd <= 0;
               end
             
             // Decode IRQ fifo data
             if (irq_fifo_check_resp)
               begin
                  // Calculate new IRQs
                  // Up to 4 IRQs come in the following lanes
                  casez (irq_fifo_rddata)
                    32'h0000??00: begin irq_new_cnt <= 1; IRQCNT <= IRQCNT + 1; end
                    32'h00????00: begin irq_new_cnt <= 2; IRQCNT <= IRQCNT + 2; end
                    32'h??????00: begin irq_new_cnt <= 3; IRQCNT <= IRQCNT + 3; end
                    32'h????????: begin irq_new_cnt <= 4; IRQCNT <= IRQCNT + 4; end
                  endcase
                  irq_fifo_check_resp <= 0;
               end

             // Latch each IRQ into external FIFO
             if (irq_processing)
               begin
                  if (irq_cmd)
                    begin
                       case (irq_new_cnt)
                         // Select correct IRQ
                         3'd4: IRQ_WRDATA <= irq_fifo_rddata[7:0];
                         3'd1: IRQ_WRDATA <= irq_fifo_rddata[15:8];
                         3'd2: IRQ_WRDATA <= irq_fifo_rddata[23:16];
                         3'd3: IRQ_WRDATA <= irq_fifo_rddata[31:24];
                         // Error if any other value
                         default:
                           begin
                              state <= STATE_IRQSCAN_ERROR;
                              IRQ_WRDATA <= 8'h01;
                              IRQ_WREN <= 1;
                           end
                       endcase // case (irq_new_cnt)

                       // Decrement counter
                       irq_new_cnt <= irq_new_cnt - 1;
                       irq_cmd <= 0;
                    end
                  else
                    begin
                       // Check if we're done
                       if (irq_new_cnt == 0)
                         begin
                            irq_processing <= 0;
                            IRQ_WREN <= 0;
                         end
                       else
                       begin
                          // Write command header
                          IRQ_WRDATA <= {4'b0001, 3'(32'(irq_new_cnt) - 1), 1'b0};
                          IRQ_WREN <= 1;
                          irq_cmd <= 1;
                       end
                    end
               end
             // Latch ahb data next cycle
             if (ahb_latch_data)
               begin
                  $display ("%H", HWDATA);
                  ahb_data <= HWDATA;
                  ahb_latch_data <= 0;
               end                    
          end // else: !if(~ENABLE | ~RESETn)
        
        // State machine
        case (state)

          STATE_DISABLED:
            begin

               // Once enabled write DP_SEL and cache AP_CSW
               if (ENABLE)
                 state <= STATE_WRITE_DPSELECT;
               else
                 begin
                    // Reset all variables
                    tar <= -1;
                    ahb_addr <= -1;
                    ahb_pending <= 0;
                    ahb_latch_data <= 0;
                    resp_pending <= 0;
                    resp_recvd <= 0;
                    check_resp <= 0;
                    slv_HREADYOUT <= 1;
                    STAT <= STAT_OK;
                    ADIv5_WREN <= 0;
                    init_complete <= 0;
                    irq_scan_active <= 0;
                    irq_scan_error <= 0;
                    irq_processing <= 0;
                    irq_fifo_check_resp <= 0;
                 end
            end
          
          STATE_IDLE:
            begin
               // Clear WREN after UPDATE_APCSW
               ADIv5_WREN <= 0;

               // No current error
               slv_HRESP <= HRESP_OKAY;

               // If autoincrement changed then update csw
               if (SEQ != csw.autoinc[0])
                 state <= STATE_WRITE_DPSELECT;

               // Complete AHB transaction
               // Same path for initiating IRQSCAN
               else if (ahb_pending | (IRQSCAN & !irq_scan_error))
                 begin
                    
                    // Clear pending for AHB access
                    if (!IRQSCAN)
                      ahb_pending <= 0;
                    
                    // Determine how to most efficiently handle the request
                    // This is actually a somewhat complicated decision tree.
                    // NOTE: This causes a wait state which is necessary for
                    // the case where we are writing directly to DRW. AHB
                    // data will latch in parallel to this state.
                    
                    // If size mismatch handle that first
                    if (ahb_req_sz != csw.width)
                      begin
                         if (bank_match (sel, AP_ADDR_CSW))
                           state <= STATE_SET_CSW;
                         else
                           state <= STATE_SELECT_APBANK_0;
                      end
                    // If TAR exact match and width is correct then access DRW
                    // For IRQSCAN we want to access via BDn
                    else if ((ahb_addr == tar) & !IRQSCAN)
                      begin
                         if (bank_match (sel, AP_ADDR_DRW))
                           state <= STATE_ACCESS_DRW;
                         else
                           state <= STATE_SELECT_APBANK_0;
                      end
                    // BDn not consistent with autoinc or non-word width
                    else if ((ahb_req_sz != CSW_WIDTH_WORD) || (ahb_addr[31:4] != tar[31:4]))
                      begin
                         // Check if bank matches TAR/CSW bank
                         if (bank_match (sel, AP_ADDR_TAR))
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
                         if (bank_match (sel, AP_ADDR_BD0))
                           state <= STATE_ACCESS_BDn;
                         else
                           state <= STATE_SELECT_APBANK_1;
                      end
                 end // if (ahb_pending)


            end // case: STATE_IDLE

          STATE_IRQSCAN:
            begin
               // Cancel if AHB request pending or scan deasserted
               if (ahb_pending | !IRQSCAN)
                 begin
                    state <= STATE_IDLE;
                    ADIv5_WREN <= 0;
                    irq_fifo_wren <= 0;
                 end
               // Keep one command issued in queue
               else if (!ADIv5_INHIBIT & cmd_complete)
                 begin
                    // Set IRQ scan as active
                    irq_scan_active <= 1;

                    // If we were processing but all IRQs have
                    // now cleared then clear all ACKs and continue
                    // scanning
                    if (|irq_prev & (resp.data == 0))
                      begin
                         ADIv5_WRDATA <= AP_REG_WRITE (AP_ADDR_BD1, 32'h0);
                         irq_ack <= 32'h0;
                      end
                    else
                      // Write READ request to BD0 continuously.
                      // The results will be checked in parallel
                      ADIv5_WRDATA <= AP_REG_READ (AP_ADDR_BD0);
                    ADIv5_WREN <= 1;
                    resp_pending <= resp_pending + 1;
                    
                    // Check previous results
                    // If theres a change push into fifo
                    if (|resp.data && (irq_prev != resp.data))
                      begin
                         // Error if FIFO fills up
                         if (irq_fifo_wrfull & irq_fifo_wren)
                           begin
                              state <= STATE_IRQSCAN_ERROR;
                              IRQ_WRDATA <= 8'h01;
                              IRQ_WREN <= 1;
                           end
                         // Push data onto internal FIFO for parallel processing
                         else
                           begin
                              irq_prev <= resp.data;
                              irq_fifo_wrdata <= resp.data;
                              irq_fifo_wren <= 1;
                           end
                      end
                    else
                      irq_fifo_wren <= 0;
                 end
               // Terminate write if FIFO full
               else
                 begin
                    irq_fifo_wren <= 0;
                    ADIv5_WREN <= 0;
                 end
            end

          // Send ACK when received from host
          STATE_IRQSCAN_ACK:
            begin
               if (!ADIv5_INHIBIT & cmd_complete)
                 begin
                    // Write IRQ ACK to ack word
                    ADIv5_WRDATA <= AP_REG_WRITE (AP_ADDR_BD1, irq_ack);
                    ADIv5_WREN <= 1;
                    resp_pending <= resp_pending + 1;

                    // Move back to scanning state
                    // if new ack not coming in
                    if (!irq_check_ack)
                      state <= STATE_IRQSCAN;
                 end
               else
                 ADIv5_WREN <= 0;
            end
          
          // IRQ scan error, exit scan and write error code
          // to interface.
          // TODO: Add sticky bit CSR to clear/inhibit
          STATE_IRQSCAN_ERROR:
            begin
               // Update flags
               irq_scan_active <= 0;
               irq_scan_error <= 1;
               state <= STATE_IDLE;
               IRQ_WREN <= 0;
            end

          // Write data to core reg
          STATE_COREREG_WRITE:
            if (!ADIv5_INHIBIT)
              begin
                 ADIv5_WRDATA <= AP_REG_WRITE (AP_ADDR_BD2, core_reg.data);
                 ADIv5_WREN <= 1;
                 resp_pending <= resp_pending + 1;

                 // Poll for complete
                 state <= STATE_COREREG_ACCESS;
              end
            else
              ADIv5_WREN <= 0;            
            
          // Send read/write command
          STATE_COREREG_ACCESS:
            if (!ADIv5_INHIBIT)
              begin
                 ADIv5_WRDATA <= AP_REG_WRITE (AP_ADDR_BD1, {16'h0, core_reg.wnr, 10'h0, core_reg.sel});
                 ADIv5_WREN <= 1;
                 resp_pending <= resp_pending + 1;

                 // Poll for complete
                 state <= STATE_COREREG_POLL_DHCSR;
              end
            else
              ADIv5_WREN <= 0;
          
          // Wait for core reg access to complete
          STATE_COREREG_POLL_DHCSR:
            begin
               // Check if command complete
               if (cmd_complete & resp.data[16])
                 begin
                    // Clear write enable
                    ADIv5_WREN <= 0;

                    // If this was a write we are done
                    if (core_reg.wnr)
                      state <= core_reg.next;
                    else
                      state <= STATE_COREREG_READ_DCRDR;
                 end
               // Issue another read
               else if (!ADIv5_INHIBIT & cmd_complete)
                 begin
                    ADIv5_WRDATA <= AP_REG_READ (AP_ADDR_BD0);
                    ADIv5_WREN <= 1;
                    resp_pending <= resp_pending + 1;
                 end
               else
                 ADIv5_WREN <= 0;
            end 

          // Read result
          STATE_COREREG_READ_DCRDR:
            begin
               // Once READY polling is flushed, send read
               if (!ADIv5_INHIBIT)
                 begin
                    // Read xPSR reg
                    ADIv5_WRDATA <= AP_REG_READ (AP_ADDR_BD2);
                    ADIv5_WREN <= 1;
                    resp_pending <= resp_pending + 1;
                    state <= STATE_COREREG_DCRDR_LATCH;
                 end
               else
                 ADIv5_WREN <= 0;
            end
            
          // Latch core register
          STATE_COREREG_DCRDR_LATCH:
            begin
               ADIv5_WREN <= 0;

               // Check if complete
               if (cmd_complete)
                 begin
                    // Latch onto outgoing FIFO
                    core_reg.data <= resp.data;

                    // Return to state
                    state <= core_reg.next;
                 end
            end
            
               
          // Update CSW to reflect autoincrement change
          STATE_UPDATE_APCSW:
            if (!ADIv5_INHIBIT)
              begin
                 // Update CSW
                 csw.autoinc <= csw_f_inc'({1'b0, SEQ});
                 ADIv5_WRDATA <= AP_REG_WRITE (AP_ADDR_CSW, {csw[31:6], 1'b0, SEQ, csw[3:0]});
                 ADIv5_WREN <= 1;
                 resp_pending <= resp_pending + 1;
                 state <= STATE_IDLE;
              end
            else
              ADIv5_WREN <= 0;

          // Write DP Select
          STATE_WRITE_DPSELECT:
            if (!ADIv5_INHIBIT)
              begin
                 // Note: We don't change APSEL. That's inherited
                 // from configuration before enabling bridge
                 //                       
                 // Clear dpbank - We don't use it for bridge
                 sel.dpbank <= 0;
                 // Set apbank for CSW read
                 sel.apbank <= 0;
                 sel.apsel <= APSEL;                      
                 // Send READ_AP command
                 ADIv5_WRDATA <= DP_REG_WRITE (DP_ADDR_SELECT, {APSEL, sel[23:8], 8'h0});
                 ADIv5_WREN <= 1;
                 resp_pending <= resp_pending + 1;
                 // Decide whether we are initializing or updating
                 // autoincrement
                 if (init_complete)
                   state <= STATE_UPDATE_APCSW;
                 else
                   state <= STATE_CACHE_APCSW;
              end
            else
              ADIv5_WREN <= 0;
          
          // Cache AP_CSW
          STATE_CACHE_APCSW:
            if (!ADIv5_INHIBIT)
              begin
                 // Send READ_AP command
                 ADIv5_WRDATA <= AP_REG_READ (AP_ADDR_CSW);
                 ADIv5_WREN <= 1;
                 resp_pending <= resp_pending + 1;
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
                    csw <= {1'b1, resp.data[30:0]};
                    // Put into IDLE
                    state <= STATE_IDLE;
                    // Init is now complete
                    init_complete <= 1;
                 end
            end
          
          // Access DRW directly
          STATE_ACCESS_DRW:
            if (!ADIv5_INHIBIT)
              begin
                 // Directly access DRW
                 ADIv5_WREN <= 1;
                 resp_pending <= resp_pending + 1;
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
            if (!ADIv5_INHIBIT)
              begin
                 ADIv5_WREN <= 1;
                 resp_pending <= resp_pending + 1;
                 if (ahb_wnr)
                   ADIv5_WRDATA <= AP_REG_WRITE (AP_ADDR_BD0 | {4'h0, ahb_addr[3:2]}, ahb_data);
                 else
                   ADIv5_WRDATA <= AP_REG_READ (AP_ADDR_BD0 | {4'h0, ahb_addr[3:2]});
                 // If not handling AHB req enter IRQSCAN
                 if (!slv_HREADYOUT)
                   state <= STATE_AHB_RESP;
                 else
                   state <= STATE_IRQSCAN;
              end
            else
              ADIv5_WREN <= 0;
          
          // Switch to apbank 0
          STATE_SELECT_APBANK_0:
            if (!ADIv5_INHIBIT)
              begin
                 sel.apbank <= 0;
                 ADIv5_WRDATA <= DP_REG_WRITE (DP_ADDR_SELECT, {sel[31:8], 4'h0, 4'h0});
                 ADIv5_WREN <= 1;
                 resp_pending <= resp_pending + 1;
                 
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
            if (!ADIv5_INHIBIT)
              begin
                 sel.apbank <= 1;
                 ADIv5_WRDATA <= DP_REG_WRITE (DP_ADDR_SELECT, {sel[31:8], 4'h1, 4'h0});
                 ADIv5_WREN <= 1;
                 resp_pending <= resp_pending + 1;
                 
                 // If we're handling an AHB3 request access BDn
                 if (!slv_HREADYOUT)
                   state <= STATE_ACCESS_BDn;
                 // Otherwise move to IRQ scan
                 else
                   state <= STATE_IRQSCAN;
              end
            else
              ADIv5_WREN <= 0;
               
          // Set CSW width
          STATE_SET_CSW:
            if (!ADIv5_INHIBIT)
              begin
                 // Save new size
                 csw.width <= csw_f_width'(ahb_req_sz);
                 ADIv5_WRDATA <= AP_REG_WRITE (AP_ADDR_CSW, {csw[31:3], ahb_req_sz});
                 ADIv5_WREN <= 1;
                 resp_pending <= resp_pending + 1;
                 // If TAR already matches
                 if ((ahb_addr == tar) && !slv_HREADYOUT)
                   state <= STATE_ACCESS_DRW;
                 // else set TAR
                 else
                   state <= STATE_SET_TAR;
              end
            else
              ADIv5_WREN <= 0;
          
          // Set TAR address
          STATE_SET_TAR:
            if (!ADIv5_INHIBIT)
              begin
                 tar <= ahb_addr;
                 ADIv5_WRDATA <= AP_REG_WRITE (AP_ADDR_TAR, ahb_addr);
                 ADIv5_WREN <= 1;
                 resp_pending <= resp_pending + 1;

                 // If we're handling an AHB3 request access DRW
                 if (!slv_HREADYOUT)
                   state <= STATE_ACCESS_DRW;
                 // Otherwise we are IRQ scanning.
                 // Select APBANK1 for scanning BDn
                 else
                   state <= STATE_SELECT_APBANK_1;
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
                    
                    // Latch read data onto AHB3 bus
                    if (!ahb_wnr)
                      begin
                         slv_HRDATA <= resp.data;
                         $display ("%H", resp.data);
                      end

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
             ahb_req_sz <= {1'b0, HSIZE[1:0]};
             
             // If write latch data next cycle
             if (HWRITE)
               ahb_latch_data <= 1;
             
             // Process next IDLE cycle
             ahb_pending <= 1;

             // Debug display
             $write ("%s%s:%H: ", HWRITE ? "W" : "R", 
                     (HSIZE[1:0] == 0) ? "B" : 
                     ((HSIZE[1:0] == 1) ? "H" : "W"), HADDR);
             
          end // if (HSEL &...
     end // always @ (posedge CLK)

endmodule // ahb3lite_remote_bridge


