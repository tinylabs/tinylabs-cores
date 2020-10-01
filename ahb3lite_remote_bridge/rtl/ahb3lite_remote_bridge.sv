/**
 *  Bridge remote target over JTAG/SWD interface.
 *  Control registers to establish connection.
 *  Transparent bridge with fixed mapping after connection is established.
 * 
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */

// Macro to access interface layer
`define ACCESS(next, apflag, adr, wrflg, data)  \
begin                                    \
   if (if_ready && !if_valid)            \
     begin                               \
        if_apndp <= apflag;              \
        if_addr <= adr;                  \
        if_valid <= 1;                   \
        if_dati <= data;                 \
        if_write <= wrflg;               \
     end                                 \
   else if (if_ready)                    \
     begin                               \
        if_valid <= 0;                   \
        state <= next;                   \
     end                                 \
end
`define DP_WRITE(next, adr, data)  `ACCESS(next, 1'b0, adr, 1'b1, data)
`define DP_READ(next, adr)         `ACCESS(next, 1'b0, adr, 1'b0, 32'h0)
`define AP_WRITE(next, adr, data)  `ACCESS(next, 1'b1, adr, 1'b1, data)
`define AP_READ(next, adr)         `ACCESS(next, 1'b1, adr, 1'b0, 32'h0)

// IRQ address to scan
`define IRQ_BASE       32'hE000E280
// Config status words
`define CSW_CFG        28'hA200000

// Invalidate cache
`define INVALIDATE_CACHE(idx)  cache_ap[idx][34] <= 1'b1;

module ahb3lite_remote_bridge 
  # ( parameter BASE_ADDR = 32'h80000000 )
   (
    // Core signals
    input                CLK,
    input                RESETn,

    // Control signals
    input                EN,
    input [4:0]          CLKDIV,

    // CTRL = APnDP | ADDR[2] | WRnRD | START
    input [4:0]          CTRLI,
    output [4:0]         CTRLO,
    input [31:0]         DATI,
    output [31:0]        DATO,
    output logic [2:0]   STAT,

    // Enable bridge after configuration done
    input                AHB_EN,
    input [7:0]          AHB_APSEL,
    
    // Debug port ID
    output [31:0]        IDCODE,

    // 8x 32MB remap registers - top bit ignored
    input [7:0] [7:0]    REMAP32M,

    // 1x 256MB remap register
    input [3:0]          REMAP256M,

    // IRQ mask/output
    input                IRQ_SCAN_EN,
    input [2:0]          IRQ_LEN,
    input [2:0]          IRQ_OFF,
    input [127:0]        IRQ_MASK,
    output logic [127:0] IRQ, 
    
    // Transparent AHB slave bridge
    input                HREADY,
    input                HWRITE,
    input                HSEL,
    input [1:0]          HTRANS,
    input [2:0]          HSIZE,
    input [31:0]         HADDR,
    input [2:0]          HBURST,
    input [3:0]          HPROT,
    input [31:0]         HWDATA,
    output logic         HREADYOUT,
    output logic [31:0]  HRDATA,
    output logic         HRESP,

    // SWD hardware interface
    input                SWDIN,
    output               SWDOUT,
    output               SWDOE,
    output               SWDCLK
   );

   // Default slave when bridge is disabled, mux outputs
   logic [31:0]                 dslv_HRDATA, slv_HRDATA;
   logic                        dslv_HREADYOUT, slv_HREADYOUT;
   logic                        dslv_HRESP, slv_HRESP;
   assign HRDATA    = EN ? slv_HRDATA    : dslv_HRDATA;
   assign HRESP     = EN ? slv_HRESP     : dslv_HRESP;
   assign HREADYOUT = EN ? slv_HREADYOUT : dslv_HREADYOUT;
   ahb3lite_default_slave
     u_default_slave (
                      .CLK        (CLK),
                      .RESETn     (RESETn),
                      .HSEL       (HSEL & ~EN),
                      .HTRANS     (HTRANS),
                      .HREADY     (HREADY),
                      .HREADYOUT  (dslv_HREADYOUT),
                      .HRESP      (dslv_HRESP),
                      .HRDATA     (dslv_HRDATA)
                      );
   
   // Borrow constants from ahb3lite package
   import ahb3lite_pkg::*;
   
   // State machine
   typedef enum logic [5:0] {
                             STATE_DISABLED,      // 0: Interface disabled
                             STATE_IDLE,          // 1: Waiting for command
                             STATE_DIRECT_RW,     // 2: Direct DP/AP read/write access
                             STATE_DIRECT_RES,    // 3:
                             STATE_CFG_CSW_SEL,   // 4: Select CSW if doesn't match AHB access
                             STATE_CFG_CSW_WR,    // 5:
                             STATE_CFG_WAIT,      // 6:
                             STATE_AHB_PROCESS,   // 7: Process AHB transaction
                             STATE_AHB_TAR_SEL,   // 8: Select TAR register
                             STATE_AHB_SELECT,    // 9:
                             STATE_AHB_TAR_WR1,   // 10: Write to TAR reg
                             STATE_AHB_TAR_WR2,   // 11: 
                             STATE_AHB_DRW_SEL,   // 12:
                             STATE_AHB_DRW_WR,    // 13:
                             STATE_AHB_DRW_RD,    // 14:
                             STATE_AHB_DRW_SAVE,  // 15:
                             STATE_AHB_DRW_RES,   // 16:
                             STATE_AHB_BD_SEL,    // 17: Select BD(0-3) reg
                             STATE_AHB_BD_WR,     // 18: Write BD(0-3) reg
                             STATE_AHB_BD_RD,     // 19: Read BD(0-3) reg
                             STATE_AHB_BD_SAVE,   // 20:
                             STATE_AHB_BD_RES,    // 21: Get BD(0-3) result
                             STATE_AHB_RESP,      // 22: Return AHB response
                             STATE_AHB_ERROR,     // 23: AHB addressing error
                             STATE_IRQ_TAR_SEL,   // 24: Point TAR to pending clear
                             STATE_IRQ_TAR_WR,    // 25:
                             STATE_IRQ_BD_SEL,    // 26:
                             STATE_IRQ_BD_RD,     // 27:
                             STATE_IRQ_SAVE,      // 28:
                             STATE_IRQ_ASSERT,    // 29: Assert IRQ locally
                             STATE_IRQ_CLR,       // 30: Clear remote IRQ
                             STATE_IRQ_FINAL,     // 31:
                             STATE_ABORT_CLR,     // 32: Abort prev transactions
                             STATE_ABORT_WAIT     // 33:
                             } brg_state_t;
   brg_state_t state;
 

   // CTRL register
   typedef enum logic [2:0] {
                             SUCCESS       = 0,  // No error
                             ERR_FAULT     = 1,  // Fault (recoverable?)
                             ERR_TIMEOUT   = 2,  // Operation timed out
                             ERR_NOCONNECT = 3,  // Remote not connected
                             ERR_PARITY    = 4,  // Parity error
                             ERR_NOMEMAP   = 5,  // No MEM-AP found
                             ERR_UNSUPSZ   = 6,  // HWRD/BYTE not supported
                             ERR_UNKNOWN   = 7   // Unknown error
                             } err_t;

   // AHB interface
   logic [31:0]        ahb_tar;     // Cache of tar value
   logic [31:0]        ahb_addr;    // AHB address to access
   logic [31:0]        ahb_data;    // data to read/write
   logic               ahb_wnr;     // Write=1 Read=0
   logic [3:0]         ahb_bd;      // Banked data reg 0/4/8/c
   logic               ahb_pending; // AHB transaction pending
   logic               ahb_latch_data; // Latch data next cycle
   logic               ahb_fixed_sz;  // Set to 1 if only word is supported
   logic [1:0]         ahb_sz;        // Current configured access 0=byte 1=hwrd 2=word
   logic [1:0]         ahb_req_sz;    // Requested size

   // AP cache is used for more efficient IRQ scanning
   // it consists of a 3bit BD val (0-3=valid 4=invalid)
   logic [1:0] [34:0]  cache_ap;
   logic               cache_idx;
   
   // SWD IF interface
   logic               if_enable;
   logic               if_apndp;
   logic [1:0]         if_addr;
   logic [31:0]        if_dati;
   logic [31:0]        if_dato;
   logic               if_write;
   logic               if_valid;
   logic               if_ready;
   logic [2:0]         if_err;
   logic               if_clr;

   // Bridge clock generation (DIV2 - DIV512)
   logic               SWDCLKIN;
   clkdiv u_bridge_clk (
                        .CLKIN   (CLK),
                        .RESETn  (RESETn),
                        .DIV     (CLKDIV),
                        .CLKOUT  (SWDCLKIN)
                        );

   /* Clear CTRLO bit[0] after transaction complete */
   assign CTRLO = if_ready && (state == STATE_DIRECT_RES) ? {CTRLI[4:1], 1'b0} : CTRLI;

   // Assign output data if READ and state machine is complete
   assign DATO = if_ready && (state == STATE_DIRECT_RES) && !CTRLI[1] ? if_dato : DATI;

   // Convert address to mask
   function [28:25] addr_mask (input [31:0] addr);
     addr_mask = addr[28:25];
   endfunction // addr_mask

   genvar              n;
   
   // SWD interface
   swd_if u_swd_if (
                    // Core signals
                    .CLK       (CLK),
                    .RESETn    (RESETn),
                    .EN        (if_enable),
                    // Hardware interface
                    .SWDIN     (SWDIN),
                    .SWDCLKIN  (SWDCLKIN),
                    .SWDCLKOUT (SWDCLK),
                    .SWDOUT    (SWDOUT),
                    .SWDOE     (SWDOE),
                    // Register interface
                    .APnDP     (if_apndp),
                    .ADDR      (if_addr),
                    .DATI      (if_dati),
                    .DATO      (if_dato),
                    .WRITE     (if_write),
                    // Flags
                    .VALID     (if_valid),
                    .READY     (if_ready),
                    .IDCODE    (IDCODE),
                    .ERR       (if_err),
                    .CLR       (if_clr)
                    );
   
   // Remote AHB bridge
   always @(posedge CLK)
     begin
        if (!RESETn)
          begin
             state <= STATE_DISABLED;
             if_enable <= 0;
          end

        // Main processing
        else
          begin

             // Check for errors on interface
             if (|if_err)
               begin
                  STAT <= if_err;
                  if_clr <= 1;
                  state <= STATE_IDLE;
               end
             else
               if_clr <= 0;
             
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

                    // Once enabled goto IDLE
                    if (if_enable && if_ready)
                      state <= STATE_IDLE;
                    else if (EN)
                      if_enable <= 1;
                    else
                      begin
                         // Reset all variables
                         ahb_tar <= -1;
                         ahb_addr <= -1;
                         ahb_pending <= 0;
                         ahb_latch_data <= 0;
                         slv_HREADYOUT <= 1;
                         IRQ <= 0;
                         STAT <= 0;
                         `INVALIDATE_CACHE (0);
                         `INVALIDATE_CACHE (1);
                      end
                 end

               STATE_IDLE:
                 begin

                    // No current error
                    slv_HRESP <= 0;

                    // Change states if disabled
                    if (!EN)
                      begin
                         state <= STATE_DISABLED;
                         if_enable <= 0;
                      end

                    // Direct access start
                    else if (CTRLI[0])
                      state <= STATE_DIRECT_RW;
                                        
                    // Complete AHB transaction
                    else if (AHB_EN & ahb_pending)
                      begin
                         if (ahb_req_sz != ahb_sz)
                           state <= STATE_CFG_CSW_SEL;
                         else
                           state <= STATE_AHB_PROCESS;                       
                      end
                    // Scan for IRQs if nothing else to do
                    else if (AHB_EN & IRQ_SCAN_EN & |IRQ_LEN & |IRQ_MASK)
                      begin
                         // Reset ahb if outside len (0-4)
                         if ({1'b0, ahb_bd[3:2]} >= ((IRQ_OFF[1:0] + IRQ_LEN) % 4))
                           ahb_bd <= {IRQ_OFF[1:0], 2'b00};

                         // Update size if not word
                         if (ahb_sz != 2)
                           begin
                              ahb_req_sz <= 2;
                              state <= STATE_CFG_CSW_SEL;
                           end
                         // If TAR is correct then skip
                         else if (ahb_tar == `IRQ_BASE + 32'({IRQ_OFF[2], 4'h0}))
                           begin
                              // Optimize for very fast polling when single reg is accessed
                              if ((IRQ_LEN == 1) && (ahb_bd == {IRQ_OFF[1:0], 2'b00}))
                                state <= STATE_IRQ_BD_RD;
                              else
                                state <= STATE_IRQ_BD_SEL;
                           end
                         else
                           state <= STATE_IRQ_TAR_SEL;
                      end
                 end // case: STATE_IDLE

               // Direct access - Just pass it to lower interface
               STATE_DIRECT_RW: //          APnDP     ADDR[1:0]   WRnRD     DATA
                 `ACCESS (STATE_DIRECT_RES, CTRLI[4], CTRLI[3:2], CTRLI[1], DATI)
               
               STATE_DIRECT_RES:
                 if (if_ready)
                   begin                      
                      // Set done flag
                      state <= STATE_IDLE;
                   end

               // Config byte/hwrd/word accesses
               STATE_CFG_CSW_SEL:
                 `DP_WRITE (STATE_CFG_CSW_WR, 2'b10, {AHB_APSEL, 16'h0, 8'h0}) // CSW select

               STATE_CFG_CSW_WR:
                 `AP_WRITE (STATE_CFG_WAIT, 2'b00, {`CSW_CFG, 2'b00, ahb_req_sz}) // Write to CSW

               // Wait for configuration to complete
               STATE_CFG_WAIT:
                 if (if_ready)
                   begin
                      state <= STATE_IDLE;
                      ahb_sz <= ahb_req_sz;
                   end

               // Send abort to cancel any previous errors
               STATE_ABORT_CLR:
                 `DP_WRITE (STATE_ABORT_WAIT, 2'b00, 32'h1e)

               // Wait until complete and return to IDLE
               STATE_ABORT_WAIT:
                 if (if_ready)
                   begin
                      state <= STATE_IDLE;
                   end               
               
               // Latch in AHB write data and process
               STATE_AHB_PROCESS:
                 begin

                    // Deassert pending
                    ahb_pending <= 0;

                    // Non-word accesses or out of bounds
                    if (((ahb_req_sz != 2) && (ahb_addr != ahb_tar)) ||
                        (ahb_addr[31:4] != ahb_tar[31:4]))
                      state <= STATE_AHB_TAR_SEL;
                    // Select correct banked address from memory
                    else
                      begin
                         state <= STATE_AHB_BD_SEL;
                         ahb_bd <= {ahb_addr[3:2], 2'h0};
                      end
                 end // case: STATE_AHB_PROCESS
               
               STATE_AHB_TAR_SEL:
                 `DP_WRITE (STATE_AHB_SELECT, 2'b10, {AHB_APSEL, 16'h0, 8'h4}) // TAR select

               // Decide if we are accessing word/hwrd/byte
               STATE_AHB_SELECT:
                 if (if_ready)
                   begin
                      if (ahb_sz != 2)
                        state <= STATE_AHB_TAR_WR1;
                      else
                        state <= STATE_AHB_TAR_WR2;
                   end

               // Byte/hwrd access
               STATE_AHB_TAR_WR1:
                 begin
                    `AP_WRITE (STATE_AHB_DRW_SEL, 2'b01, ahb_addr) // Write to TAR
                    ahb_tar <= ahb_addr;
                 end

               STATE_AHB_DRW_SEL:
                 begin
                    if (ahb_wnr)
                      `DP_WRITE (STATE_AHB_DRW_WR, 2'b10, {AHB_APSEL, 16'h0, 8'hc}) // DRW select
                    else
                      `DP_WRITE (STATE_AHB_DRW_RD, 2'b10, {AHB_APSEL, 16'h0, 8'hc}) // DRW select
                 end

               // Write byte/hwrd
               STATE_AHB_DRW_WR:
                 `AP_WRITE (STATE_AHB_RESP, 2'b11, ahb_data)

               // Read word/hwrd
               STATE_AHB_DRW_RD:
                 `AP_READ (STATE_AHB_DRW_SAVE, 2'b11)
               
               STATE_AHB_DRW_SAVE:
                 if (if_ready)
                   begin
                      `INVALIDATE_CACHE (cache_idx);
                      cache_idx <= ~cache_idx;
                      state <= STATE_AHB_DRW_RES;
                   end

               // Get actual read response
               STATE_AHB_DRW_RES:
                 `DP_READ (STATE_AHB_RESP, 2'b11)
                 
               // Word access
               STATE_AHB_TAR_WR2:
                 begin
                    `AP_WRITE (STATE_AHB_BD_SEL, 2'b01, {ahb_addr[31:4], 4'h0}) // Write to TAR
                    ahb_tar <= {ahb_addr[31:4], 4'h0};
                    ahb_bd <= {ahb_addr[3:2], 2'h0};
                 end
               
               STATE_AHB_BD_SEL:
                 begin
                    if (ahb_wnr)
                      `DP_WRITE (STATE_AHB_BD_WR, 2'b10, {AHB_APSEL, 16'h0, {4'h1, ahb_bd}}) // BD select
                    else
                      `DP_WRITE (STATE_AHB_BD_RD, 2'b10, {AHB_APSEL, 16'h0, {4'h1, ahb_bd}}) // BD select
                 end
               
               STATE_AHB_BD_WR:
                 `AP_WRITE (STATE_AHB_RESP, ahb_bd[3:2], ahb_data)
               
               STATE_AHB_BD_RD:
                 `AP_READ (STATE_AHB_BD_SAVE, ahb_bd[3:2]) // Read data from banked register

               STATE_AHB_BD_SAVE:
                 if (if_ready)
                   begin
                      `INVALIDATE_CACHE (cache_idx);
                      cache_idx <= ~cache_idx;
                      state <= STATE_AHB_BD_RES;
                   end

               STATE_AHB_BD_RES:
                 `DP_READ (STATE_AHB_RESP, 2'b11)  // Get actual data from RDBUFF
               
               STATE_AHB_RESP:
                 if (if_ready)
                   begin
                      // If read latch onto bus
                      if (!ahb_wnr)
                        slv_HRDATA <= if_dato;
                      
                      // Set response and clear readyout
                      slv_HRESP <= 0; // TODO: Check for errors
                      slv_HREADYOUT <= 1;
                      state <= STATE_IDLE;
                   end // if (if_ready)

               // HRESP must be asserted for 2 cycles if HREADYOUT asserted
               STATE_AHB_ERROR:
                 begin
                    slv_HREADYOUT <= 1;
                    state <= STATE_IDLE;
                 end

               // Select TAR register to write
               STATE_IRQ_TAR_SEL:
                 `DP_WRITE (STATE_IRQ_TAR_WR, 2'b10, {AHB_APSEL, 16'h0, 8'h4}) // TAR select

               // Write base to tar register
               STATE_IRQ_TAR_WR:
                 begin
                    `AP_WRITE (STATE_IRQ_BD_SEL, 2'b01, `IRQ_BASE + 32'({IRQ_OFF[2], 4'h0})) // Write to TAR
                    ahb_tar <= `IRQ_BASE + 32'({IRQ_OFF[2], 4'h0});
                 end

               // Select banked data register
               STATE_IRQ_BD_SEL:
                 `DP_WRITE (STATE_IRQ_BD_RD, 2'b10, {AHB_APSEL, 16'h0, {4'h1, ahb_bd}}) // BD select

               // Read current BD
               STATE_IRQ_BD_RD:
                 `AP_READ (STATE_IRQ_SAVE, ahb_bd[3:2]) // Read data from banked register

               // Set local IRQs
               STATE_IRQ_SAVE:
                 if (if_ready)
                   begin
                      // Store AP read
                      cache_ap[cache_idx] <= {1'b0, ahb_bd[3:2] - IRQ_OFF[1:0], if_dato};
                      cache_idx <= ~cache_idx;
                      state <= STATE_IRQ_ASSERT;
                   end

               // Assert IRQ
               STATE_IRQ_ASSERT:
                 // Set IRQ based on previous read if valid
                 begin
                    if (cache_ap[cache_idx][34] == 0)
                      case (cache_ap[cache_idx][33:32])
                        2'b00: IRQ[31:0]   <= if_dato & IRQ_MASK[31:0];
                        2'b01: IRQ[63:32]  <= if_dato & IRQ_MASK[63:32];
                        2'b10: IRQ[95:64]  <= if_dato & IRQ_MASK[95:64];
                        2'b11: IRQ[127:96] <= if_dato & IRQ_MASK[127:96];
                      endcase // case (cache_ap[cache_idx][33:32]

                    // Clear IRQ
                    state <= STATE_IRQ_CLR;                      
                 end

               // Clear IRQ if valid
               STATE_IRQ_CLR:
                 begin
                    if (cache_ap[cache_idx][34] == 0)
                      case (cache_ap[cache_idx][33:32])
                        2'b00: `AP_WRITE (STATE_IRQ_FINAL, 2'b00, IRQ[31:0])
                        2'b01: `AP_WRITE (STATE_IRQ_FINAL, 2'b01, IRQ[63:32])
                        2'b10: `AP_WRITE (STATE_IRQ_FINAL, 2'b10, IRQ[95:64])
                        2'b11: `AP_WRITE (STATE_IRQ_FINAL, 2'b11, IRQ[127:96])
                      endcase // case (cache_ap[cache_idx][33:32]
                    else
                      state <= STATE_IRQ_FINAL;
                    
                    // Only pulse IRQ for one cycle
                    IRQ <= 0;
                   end

              
               STATE_IRQ_FINAL:
                 if (if_ready)
                   begin
                      // Increment BD if necessary
                      if (IRQ_LEN > 1)
                        ahb_bd <= ahb_bd + 4'h4;
                      
                      // Back to IDLE to handle events
                      state <= STATE_IDLE;
                   end
               default:
                 state <= STATE_IDLE;
               
             endcase // case (state)

             // Handle AHB slave requests
             if (HSEL &
                 HREADY &&
                 (HTRANS != HTRANS_BUSY) &&
                 (HTRANS != HTRANS_IDLE))
               begin

                  
                  // Set HREADYOUT as busy
                  slv_HREADYOUT <= 0;

                  // Remap address from local to remote
                  casez (addr_mask(HADDR - BASE_ADDR))
                    // 8x 32MB remaps
                    4'b0_000: ahb_addr <= {REMAP32M[0][7:1], HADDR[24:0]};
                    4'b0_001: ahb_addr <= {REMAP32M[1][7:1], HADDR[24:0]};
                    4'b0_010: ahb_addr <= {REMAP32M[2][7:1], HADDR[24:0]};
                    4'b0_011: ahb_addr <= {REMAP32M[3][7:1], HADDR[24:0]};
                    4'b0_100: ahb_addr <= {REMAP32M[4][7:1], HADDR[24:0]};
                    4'b0_101: ahb_addr <= {REMAP32M[5][7:1], HADDR[24:0]};
                    4'b0_110: ahb_addr <= {REMAP32M[6][7:1], HADDR[24:0]};
                    4'b0_111: ahb_addr <= {REMAP32M[7][7:1], HADDR[24:0]};
                    // 256MB remap (0x4000.0000 by default)                         
                    4'b1_???: ahb_addr <= {REMAP256M, HADDR[27:0]};
                  endcase
                  
                  // Save read write state
                  ahb_wnr <= HWRITE;

                  // Process next cycle
                  ahb_pending <= 1;

                  // Save transaction size
                  ahb_req_sz <= HSIZE[1:0];
                       
                  // If write latch data next cycle
                  if (HWRITE)
                    ahb_latch_data <= 1;
               end // if (HSEL &...
          end // else: !if(!RESETn)        
     end // always @ (posedge CLK)

endmodule // ahb3lite_remote_bridge


