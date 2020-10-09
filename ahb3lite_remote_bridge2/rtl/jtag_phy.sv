/**
 *  JTAG (Joint Test Action Group) PHY layer - Fully pipelined with
 *  async PHY_CLK
 * 
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */

// Update JTAG finite state machine
`define FSM(_state, _tms) begin TMS <= _tms; state <= (_state); end

module jtag_phy
  # (parameter MAX_CLEN = 1024,  // Max total scan chain length
     parameter BUF_SZ   = 32,    // Data bits per FIFO packet
     // Derived
     parameter CMD_WIDTH = 3,
     // DATA, CMD, LENGTH, STATE
     parameter FIFO_IN_SZ = (BUF_SZ + CMD_WIDTH + $clog2 (MAX_CLEN) + 4),
     // DATA, LENGTH, STATUS
     parameter FIFO_OUT_SZ = (BUF_SZ + $clog2 (BUF_SZ) + 1)
     ) 
   (
    // Core signals
    input                    CLK,
    input                    PHY_CLK,
    input                    RESETn,
    input                    ENABLE,
    
    // FIFO interface IN
    input [FIFO_IN_SZ-1:0]   WRDATA,
    input                    WREN,
    output                   WRFULL,

    // FIFO interface OUT
    output [FIFO_OUT_SZ-1:0] RDDATA,
    input                    RDEN,
    output                   RDEMPTY,

    // Hardware interface
    output logic             TCK,
    output logic             TMS,
    output logic             TDI,
    input                    TDO
    );

   // Command to pass PHY
   typedef enum logic [2:0] {
                             // No response commands
                             CMD_SHFT0        = 0, // Shift zeros no response
                             CMD_SHFT1        = 1, // Shift ones no response
                             CMD_DATA         = 2, // Shift data no response
                             CMD_NOP          = 3, // No shift operation
                             // Commands with response
                             CMD_SHFT0_RECV   = 4, // Shift zero get response
                             CMD_SHFT1_RECV   = 5, // Shift one get response
                             CMD_DATA_RECV    = 6, // Shift data onto chain
                             CMD_COUNT        = 7  // Shift single one and count
                             } cmd_t;
   
   // JTAG TAP state-machine
   // These states were chosen because state[2:0] represent a 
   // 3bit LFSR (poly=6) with a length of 7. 
   // state[4] selects DR=0/IR=1.
   // Conveniently, state[1] represents the TMS value to get to
   // next state in LFSR.
   //
   // The two illegal LFSR states are used at RUNTEST_IDLE/LOGIC_RESET.
   // Non-natural LFSR transitions are handled in special cases below.
   typedef enum logic [3:0] {
                             // Reset/IDLE
                             RUNTEST_IDLE   = 4'b0000,
                             LOGIC_RESET    = 4'b1000,
                             // DR states
                             SELECT_DR      = 4'b0001,
                             CAPTURE_DR     = 4'b0100,
                             SHIFT_DR       = 4'b0010,
                             EXIT1_DR       = 4'b0101,
                             PAUSE_DR       = 4'b0110,
                             EXIT2_DR       = 4'b0111,
                             UPDATE_DR      = 4'b0011,
                             // IR states
                             SELECT_IR      = 4'b1001,
                             CAPTURE_IR     = 4'b1100,
                             SHIFT_IR       = 4'b1010,
                             EXIT1_IR       = 4'b1101,
                             PAUSE_IR       = 4'b1110,
                             EXIT2_IR       = 4'b1111,
                             UPDATE_IR      = 4'b1011
                             } state_t;

   // Command shifted in
   cmd_t cmd, cmdp;

   // Represent current and target state
   state_t state, nstate, nstatep;
   
   // Local FIFO interface signals
   logic                           rden, wren, empty, full;
   logic                           valid, busy, done;

   // Data in/out
   logic [BUF_SZ-1:0]              din, dout, doutp;
   logic [$clog2(MAX_CLEN)-1:0]    olen, olenp, ctr;
   logic [$clog2(BUF_SZ):0]        ilen;

   
   // FIFO interfaces with layer above
   dual_clock_fifo #(.ADDR_WIDTH (2),
                     .DATA_WIDTH  (FIFO_IN_SZ))
   u_phy_in (
             // Host interface
             .wr_clk_i   (CLK),
             .wr_rst_i   (~RESETn),
             .wr_en_i    (WREN),
             .wr_data_i  (WRDATA),
             .full_o     (WRFULL),
             
             // PHY interface
             .rd_clk_i   (PHY_CLK),
             .rd_rst_i   (~RESETn),
             .rd_en_i    (rden),
             .rd_data_o  ({doutp, olenp, cmdp, nstatep}),
             .empty_o    (empty)
             );
   dual_clock_fifo #(.ADDR_WIDTH (2),
                     .DATA_WIDTH  (FIFO_OUT_SZ))
   u_phy_out (
              // Host interface
              .rd_clk_i   (CLK),
              .rd_rst_i   (~RESETn),
              .rd_en_i    (RDEN),
              .rd_data_o  (RDDATA),
              .empty_o    (RDEMPTY),
              
              // PHY interface
              .wr_clk_i   (PHY_CLK),
              .wr_rst_i   (~RESETn),
              .wr_en_i    (wren & !full),
              .wr_data_i  ({din, ilen}),
              .full_o     (full)
             );
   
   // Read when data ready and not busy
   assign rden = !empty & !valid;
   
   always @(posedge PHY_CLK, negedge PHY_CLK)
     if (!RESETn | !ENABLE)
       begin
          busy <= 0;
          TCK <= 0;
          TMS <= 0;
          TDI <= 0;
          state <= RUNTEST_IDLE;
          nstate <= RUNTEST_IDLE;
          olen <= 0;
       end
     else // Not in RESET
       begin
                   
          // Negative edge of phy clk
          if (!PHY_CLK)
            begin
               
               // Toggle postive edge
               if ((ctr <= olen) | (state != nstate))
                 TCK <= 1;
                    
               // Sample TDO on rising edge
               if ((ctr < olen) && (state == nstate))
                 begin
                                        
                    // Start sampling when counter is > 0
                    if (ctr > 0)
                      begin
                         
                         // Count until we see one
                         if (cmd == CMD_COUNT)
                           begin
                              // Terminate early when we see '1'
                              if (TDO)
                                begin
                                   ilen <= BUF_SZ;
                                   ctr <= olen - 2;
                                end
                              // Count zeros
                              else
                                din <= din + 1;
                           end
                         // Clock in TDO
                         else if (cmd[2] != 0)
                           din <= {TDO, din[BUF_SZ-1:1]};
                         
                      end // if (ctr > 0)

                 end // if (state == nstate)

            end // if (PHY_CLK)
          
          // Positive edge of PHY_CLK - setup data
          else
            begin
            
               // Toggle negative CLK edge
               if ((ctr <= olen) | (state != nstate))
                 TCK <= 0;

               // Data valid next cycle after READ
               if (rden)
                 valid <= 1;
               
               // Copy to blocking regs
               if (valid & !busy)
                 begin
                    olen <= olenp;
                    nstate <= nstatep;
                    ilen <= 0;
                    din <= 0;
                    cmd <= cmdp;
                    busy <= 1;
                    valid <= 0;
                    done <= 0;
                    
                    // Operate on command
                    casez (cmdp)
                      3'b?00:    TDI <= 0;                  // Shift zero
                      3'b?01:    TDI <= 1;                  // Shift one
                      3'b?10:    TDI <= doutp[0];            // Shift data
                      CMD_NOP:   TDI <= 0;                  // Do nothing
                      CMD_COUNT: TDI <= 1; // Shift 100000...
                    endcase // case (cmd)

                    if (cmdp[1:0] == 2'b10)
                      dout <= {1'b0, doutp[BUF_SZ-1:1]};
                    else                    
                      dout <= doutp;
                 end

               // Drive TDI on negative edge
               if ((ctr < olen) && (state == nstate))
                 begin
                                        
                    // Shift data once we are in correct state
                    if (cmd[1:0] == 2'b10)
                      begin
                         dout <= {1'b0, dout[BUF_SZ-1:1]};
                         TDI <= dout[0];
                      end
                 end

               // Reset counter
               if (state != nstate)
                 ctr <= 0;
               else if (ctr < olen)
                 ctr <= ctr + 1;

               // Write response back
               if (done)
                 begin
                    wren <= cmd[2] ? 1 : 0;
                    done <= 0;
                 end
               else
                 wren <= 0;            

               // Trigger done
               if (ctr == (olen - 2))
                 begin
                    busy <= 0;
                    done <= 1;
                    olen <= 0;
                    ilen <= ctr[$clog2(BUF_SZ):0];
                    nstate <= RUNTEST_IDLE;
                 end

               //
               // JTAG state machine
               //
               // Based on 3bit LFSR with some added logic for
               // alternate transitions.
               //
               // TMS on negative transition
               // State change on positve
               //
               
               // LOGIC_RESET/RUNTEST_IDLE
               if (state[2:0] == 3'b000) begin
                  if (nstate != state)
                    `FSM (|state ? RUNTEST_IDLE : SELECT_DR, ~TMS)
               end
               
               // Handle SELECT_DR -> SELECT_IR
               else if ((state == SELECT_DR) & nstate[3])
                 `FSM ({1'b1, state[2:0]}, TMS)
               
               // Handle SELECT_IR -> LOGIC_RESET
               else if ((state == SELECT_IR) && (nstate[2:0] == 3'b000))
                 `FSM (LOGIC_RESET, 1)
               
               // Handle skip of shift-IR/DR
               else if ((state[2:0] == 3'b100) && (nstate[2:0] != 3'b010))
                 `FSM ({state[3], 3'b101}, 1)
               
               // Handle transition from EXIT2-xx to SHIFT-xx
               else if ((state[2:0] == 3'b111) && (state[3] == nstate[3]) && 
                        (nstate[2:0] == 3'b010))
                 `FSM ({state[3], 3'b010}, 0)
                    
               // Handle UPDATE-xx transition
               else if ((state[2:0] == 3'b011) && (nstate == RUNTEST_IDLE))
                 `FSM (RUNTEST_IDLE, 0)
               
               // Handle EXIT1->UPDATE
               else if ((state[2:0] == 3'b101) && (nstate[2:0] != 3'b110))
                 `FSM ({state[3], 3'b011}, 1)
               
               // Handle SHIFT_DR/IR PAUSE_DR/IR loops
               else if ((state[1:0] == 2'b10) && (state == nstate))
                 ; // Do nothing
               
               // Drive state machine with LFSR (TMS = state[1])
               else
                 `FSM ({state[2:0] == 3'b011 ? 1'b0 : state[3], ^state[1:0], state[2:1]}, state[1])

            end // else: !if(PHY_CLK)
          
       end // else: !if(!RESETn | !ENABLE)

endmodule // jtag_phy
