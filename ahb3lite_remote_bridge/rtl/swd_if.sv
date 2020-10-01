/**
 *  SWD (serial wire debug) port logical interface.
 *  
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */

// Macro to send data over SWD
`define SWD_RAW(STATE, T0, T1, SO, LEN) \
begin                                   \
if (svalid & !sready)                   \
   begin                                \
      svalid <= 0;                      \
      state <= STATE;                   \
   end                                  \
else if (sready)                        \
   begin                                \
      t0 <= T0;                         \
      t1 <= T1;                         \
      so[$bits(SO)-1:0] <= SO;          \
      len <= LEN;                       \
      svalid <= 1;                      \
   end                                  \
end
      

// SWD macros
`define SWD_OUT(STATE, SO, LEN)     `SWD_RAW(STATE, 63, 63, SO, LEN)
`define SWD_ENABLE(STATE)           `SWD_RAW(STATE, 0, 63, 2'b11, 2)       
`define SWD_DISABLE(STATE)          `SWD_RAW(STATE, 1, 63, 2'b00, 2)       
`define REG_READ(NEXT,AnD,ADR)      `SWD_RAW(NEXT,8,45,{1'b0,3'b010,^{ADR,AnD,1'b1},ADR[1],ADR[0],1'b1,AnD,1'b1},46)
`define REG_WRITE(NEXT,AnD,ADR,DAT) `SWD_RAW(NEXT,8,12,{1'b0,^DAT,DAT,3'b010,^{ADR,AnD,1'b0},ADR[1],ADR[0],1'b0,AnD,1'b1},47)
`define READ_IDCODE                 `SWD_RAW(STATE_STORE_IDCODE,8,45,{1'b0,3'b010,^{2'b00,1'b0,1'b1},2'b00,1'b1,1'b0,1'b1},46)
`define WRITE_FLUSH                 `SWD_RAW(STATE_WAIT_IDLE, 63, 63, 8'h0, 8)
                                          
// Max retries before failing
`define MAX_RETRIES  7

module swd_if
  (
   // Core signals
   input               CLK,
   input               RESETn,
   input               EN,

   // Hardware interface
   input               SWDIN,
   input               SWDCLKIN,
   output              SWDCLKOUT,
   output              SWDOUT,
   output              SWDOE,
   
   // Register interface
   input               APnDP,  // AP=1  DP=0
   input [1:0]         ADDR,   // addr[3:2] zero extend
   input [31:0]        DATI,
   output logic [31:0] DATO,
   input               WRITE,  // 1=write 0=read

   // valid/ready flags
   input               VALID,  // Drive high when input valid
   output logic        READY,  // Goes high when output valid
   output logic [31:0] IDCODE, // IDCODE of connected target (after enabled)
   output logic [2:0]  ERR,    // Error code
   input               CLR     // Clear the error condition
   );


   // State machine
   typedef enum logic [3:0] {
                             STATE_DISABLED,    // 0: Interface is tristated (TMS=input)
                             STATE_LR_FLUSH1,   // 1: Enable transition states
                             STATE_LR_SWITCH,   // 2: '
                             STATE_LR_FLUSH2,   // 3: '
                             STATE_READ_IDCODE, // 4: Read IDCODE from target
                             STATE_STORE_IDCODE,// 5: Store IDCODE
                             STATE_WAIT_IDLE,   // 6: Wait for operation to complete
                             STATE_IDLE,        // 7: Initialized and ready for commands
                             STATE_READ_REG,    // 8: Read from register
                             STATE_WRITE_REG,   // 9: Write to register
                             STATE_DISABLE,     // 10: Disable the interface
                             STATE_VALIDATE,    // 11: Validate previous transaction
                             STATE_WRITE_FLUSH  // 12: Flush previous write
                             } swd_state_t;

   swd_state_t state;

   // Errors
   typedef enum logic [2:0] {
                             SUCCESS,        // 000
                             ERR_FAULT,      // 001
                             ERR_WAIT,       // 010
                             ERR_NOCONNECT,  // 011
                             ERR_PARITY,     // 100
                             ERR_TIMEOUT,    // 101
                             ERR_UNKNOWN = 7 // 111
                             } err_t;

   // Internal logic
   wire [2:0]   err;
   logic [2:0]  retries;

   // Shift reg variables
   logic [5:0]  t0;
   logic [5:0]  t1;
   logic [5:0]  len;
   logic [63:0] so;
   logic        svalid;
   wire [35:0]  si;
   wire         sready;
                     
   // Create swd phy
   swd_phy u_swd_phy (
                      // Core signals
                      .CLK     (CLK),
                      .RESETn  (RESETn),
                      // Hardware interface
                      .SWDCLKIN  (SWDCLKIN),
                      .SWDCLKOUT (SWDCLKOUT),
                      .SWDIN   (SWDIN),
                      .SWDOUT  (SWDOUT),
                      .SWDOE   (SWDOE),
                      // Shift reg interface
                      .T0      (t0),
                      .T1      (t1),
                      .SO      (so),
                      .SI      (si),
                      .LEN     (len),
                      .VALID   (svalid),
                      .READY   (sready),
                      .ERR     (err)
                      );
   
   always @(posedge CLK)
     begin

        // Start reset sequence
        if (!RESETn)
          begin
             state <= STATE_DISABLED;
          end

        // Main processing
        else
          begin

             // Clear error if requested
             if (CLR)
               ERR <= 0;
             
             case (state)
               
               default:
                 state <= STATE_DISABLED;
               
               // When disabled the only thing to do is enable it
               STATE_DISABLED:
                 if (EN)
                   begin
                      READY <= 0;
                      `SWD_ENABLE (STATE_LR_FLUSH1)
                   end
                 else
                   begin
                      READY <= 0;
                      ERR <= 0;
                      IDCODE <= 0;
                   end
               
               // IDLE state
               // Start read/write/line reset
               STATE_IDLE:
                 begin
                    
                    // If enable goes low deactivate interface
                    if (!EN)
                      begin
                         READY <= 0;
                         state <= STATE_DISABLE;
                      end
                    // Process new operation
                    else if (VALID)
                      begin
                         READY <= 0;
                         retries <= 0;
                         
                         // Start write operation
                         if (WRITE)
                           state <= STATE_WRITE_REG;
                         
                         // Start read operation
                         else
                           state <= STATE_READ_REG;
                         
                      end // if (VALID)
                 end // case: STATE_IDLE               

               // Disable interface
               STATE_DISABLE:
                 `SWD_DISABLE (STATE_DISABLED)
               
               // Read register
               STATE_READ_REG:
                 `REG_READ (STATE_VALIDATE, APnDP, ADDR)

               // Write register
               STATE_WRITE_REG:
                 `REG_WRITE (STATE_VALIDATE, APnDP, ADDR, DATI)
               
               // Switch to flush state
               STATE_LR_FLUSH1:
                 `SWD_OUT (STATE_LR_SWITCH, {60{1'b1}}, 60)
               
               // Switch from JTAG to SWD if SWD-JP
               STATE_LR_SWITCH:
                 `SWD_OUT (STATE_LR_FLUSH2, 16'he79e, 16)
               
               // Second line reset flush - go to IDLE state when done
               STATE_LR_FLUSH2: 
                 `SWD_OUT (STATE_READ_IDCODE, {4'h0, {56{1'b1}}}, 60)
               
               // Read IDCODE
               STATE_READ_IDCODE:
                 `READ_IDCODE

               STATE_WRITE_FLUSH:
                 `WRITE_FLUSH
               
               STATE_STORE_IDCODE:
                 begin
                    // Go back to IDLE when complete
                    if (sready & !svalid)
                      begin
                         ERR    <= err;
                         state  <= STATE_IDLE;
                         READY  <= 1;
                         IDCODE <= {<<{si[32:1]}};                         
                      end
                    else if (sready)
                      // Clear valid signal
                      svalid <= 0;
                 end
                 
               // Validate transaction before returning to IDLE
               STATE_VALIDATE:
                 begin
                    // Wait until operation is complete
                    if (sready)
                      begin
                         
                         // Handle normal case
                         if (err == SUCCESS)
                           begin

                              // Flush if set with write
                              if (WRITE & APnDP)
                                state <= STATE_WRITE_FLUSH;
                              // Back to IDLE state
                              else
                                begin
                                   state <= STATE_IDLE;
                                   READY <= 1;
                                end

                              // Handle reads
                              if (!WRITE)
                                begin
                                   // Check parity
                                   if (^si[32:0])
                                     ERR <= ERR_PARITY;
                                   else
                                     DATO <= {<<{si[32:1]}};
                                end
                              else
                                ERR <= SUCCESS;
                           end
                         // Have we exceeded max retries
                         else if (retries >= `MAX_RETRIES)
                           begin
                              ERR <= ERR_TIMEOUT;
                              state <= STATE_IDLE;
                              READY <= 1;
                           end
                         // Retry operation
                         else if (err == ERR_WAIT)
                           begin
                              // Reissue operation
                              if (WRITE)
                                state <= STATE_WRITE_REG;
                              else
                                state <= STATE_READ_REG;

                              // Increment retries
                              retries <= retries + 1;
                           end // if (err == ERR_WAIT)
                         else
                           // Save error code and return
                           begin
                              ERR <= err;
                              state <= STATE_IDLE;
                              READY <= 1;
                           end

                      end // if (sready)

                 end // case: STATE_VALIDATE
               
               // Wait for operation to finish
               STATE_WAIT_IDLE:                  
                 begin

                    // Go back to IDLE when complete
                    if (sready & !svalid)
                      begin
                         state <= STATE_IDLE;
                         READY <= 1;
                      end
                    else if (sready)
                      // Clear valid signal
                      svalid <= 0;
                 end // case: STATE_WAIT_IDLE
                              
             endcase
          end
     end
      
endmodule : swd_if

