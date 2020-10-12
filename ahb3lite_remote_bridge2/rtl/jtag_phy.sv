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
  # (parameter MAX_CLEN = 4096,  // Max total scan chain length
     parameter BUF_SZ   = 64,    // Data bits per FIFO packet
     // Fixed CMD width
     parameter CMD_WIDTH = 3,
     // Derived
     // DATA, LENGTH, CMD
     parameter FIFO_IN_SZ = (BUF_SZ + CMD_WIDTH + $clog2 (MAX_CLEN)),
     // DATA, LENGTH
     parameter FIFO_OUT_SZ = (BUF_SZ + $clog2 (BUF_SZ))
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
   // 3 bit commands
   // DR/IR | AUTO_EXTEND | CAPTURE_OUTPUT
   // DR=0 IR=1
   // AUTO_EXTEND = 0/1
   //   auto-extend replicates the msb when shifting data 
   //   into the output register.
   // CAPTURE_OUTPUT = 0/1
   //
   // 0 = 000 = Write DR
   // 1 = 001 = Read DR
   // 2 = 010 = Write DR auto-extend
   // 3 = 011 = Read DR auto-extend
   // 4 = 100 = Write IR
   // 5 = 101 = Read IR
   // 6 = 110 = Write IR auto-extend
   // 7 = 111 = Read IR auto-extend
   
   // Command and shadow
   logic [2:0]  cmd, cmdp;
   
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

   // Represent current and target state
   state_t state, nstate;
   
   // Local FIFO interface signals
   logic                           rden, wren, empty, full;
   logic                           dvalid, busy;

   // Data in/out
   logic [BUF_SZ-1:0]              din, dout, doutp;
   logic [$clog2(MAX_CLEN)-1:0]    olen, olenp, ctr;
   logic [$clog2(BUF_SZ)-1:0]      ilen;
   
   
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
             .rd_data_o  ({doutp, olenp, cmdp}),
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
              .wr_en_i    (wren),
              .wr_data_i  ({din, ilen}),
              .full_o     (full)
             );
   
   // Read when data ready and in IDLE or reset
   assign rden = !empty & !busy;
   
   always @(posedge PHY_CLK, negedge PHY_CLK)
     if (!RESETn | !ENABLE)
       begin
          TCK <= 0;
          TDI <= 0;
          TMS <= 1;
          state  <= LOGIC_RESET;
          nstate <= LOGIC_RESET;
          // Internal vars
          busy <= 0;
       end
     else // Not in RESET
       begin
                   
          // Negative edge of phy clk
          if (!PHY_CLK)
            begin

               // Toggle clock while enabled
               TCK <= 1;

               // Clear write enable
               if (wren)
                 wren <= 0;
                    
               // If reading back data
               if (cmd[0])
                 begin
                    
                    // Shift in on SHIFT-XX
                    if (state[2:0] == 3'b010)
                      begin
                         din <= {TDO, din[BUF_SZ-1:1]};
                         ilen <= ilen + 1;
                      end

                    // Check if we are done
                    if (ctr == olen - 1)
                      begin
                         wren <= 1;
                         cmd <= 0;
                         ilen <= ilen;
                      end

                 end // if (cmd[0])               
               
            end // if (PHY_CLK)
          
          // Positive edge of PHY_CLK - setup data
          else
            begin

               // Toggle clock while enabled
               TCK <= 0;

               // Shift out bits if in capture-XX state or EXIT1-XX state
               if ((state[2:0] == 3'b010) || (state[2:0] == 3'b101))
                 begin

                    // Drive TDI
                    TDI <= dout[0];
                    
                    // Auto-extend if enabled
                    dout <= cmd[1] ? {dout[BUF_SZ-1], dout[BUF_SZ-1:1]} : {1'b0, dout[BUF_SZ-1:1]};
               
                    // TODO - Move to Pause state if we run out
                    // of input data
                    
                    // TODO - Clr busy when out of data
                    if (ctr < olen)
                      begin
                         
                         // Increment counter
                         ctr <= ctr + 1;
                      end
                    
                    // Transition out two cycles early
                    if (ctr == olen - 2)
                      begin
                         // Move back to IDLE when done
                         nstate <= RUNTEST_IDLE;
                         busy <= 0;
                      end

                 end // if ((state[2:0] == 3'b010) || (state[2:0] == 3'b101))
               
               //
               // Latch in new command to shadow regs
               //
               if (rden)
                 begin
                    dvalid <= 1;
                    busy <= 1;
                 end
                     
               // If data is valid then latch into operating regs
               if (dvalid)
                 begin
                    cmd <= cmdp;
                    olen <= cmdp[0] ? olenp + 1 : olenp;
                    dout <= doutp;
                    dvalid <= 0;
                    
                    // Reset counter
                    ctr <= 0;

                    // Clear din
                    din <= 0;
                    
                    // Move to RESET
                    if (olenp == 0)
                      nstate <= LOGIC_RESET;
                    // Move to SHIFT-IR
                    else if (cmdp[2])
                      nstate <= SHIFT_IR;
                    // Move to SHIFT-DR
                    else
                      nstate <= SHIFT_DR;
                 end // if (dvalid)
               
               
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
