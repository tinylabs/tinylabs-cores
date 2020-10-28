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

localparam JTAG_CMD_WIDTH   = 79;
localparam JTAG_RESP_WIDTH  = 70;

module jtag_phy
  # (parameter MAX_CLEN = 4096,  // Max total scan chain length
     parameter BUF_SZ   = 64,    // Data bits per FIFO packet
     // FIFO width
     parameter FIFO_AW = 2,
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
   //
   // Special cases
   // len = 0
   //   cmd == 000 - RESET
   //   cmd == 100 - JTAG SWITCH
   //   cmd == 110 - Insert 8 IDLE cycles
   
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
   state_t      state, nstate, pstate;

   // Blocking FIFO state
   logic        resp_blocked, req_blocked;
   
   // Local FIFO interface signals
   logic        rden, wren, empty, full;
   logic        dvalid, busy, pending;
   
   // Data in/out
   logic [BUF_SZ-1:0]           din, dout, doutp;
   logic [$clog2(MAX_CLEN)-1:0] olen, olenp, ctr;
   logic [$clog2(BUF_SZ)-1:0]   ilen;

   logic                        gate_tck;

   // Gate TCK when IDLE - save power
   assign gate_tck = ((state == RUNTEST_IDLE) && !pending);

   // FIFO interfaces with layer above
   dual_clock_fifo #(.ADDR_WIDTH (FIFO_AW),
                     .DATA_WIDTH (FIFO_IN_SZ))
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
   dual_clock_fifo #(.ADDR_WIDTH (FIFO_AW),
                     .DATA_WIDTH (FIFO_OUT_SZ))
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
   assign rden = !empty & !dvalid & !busy;
   
   always @(posedge PHY_CLK, negedge PHY_CLK)
     if (!RESETn)
       begin
          TCK <= 0;
          TDI <= 0;
          TMS <= 1;
          state  <= LOGIC_RESET;
          nstate <= LOGIC_RESET;
          // Internal vars
          busy <= 0;
          resp_blocked <= 0;
          req_blocked <= 0;
          pending <= 0;
       end
     else // Not in RESET
       begin
                   
          // Negative edge of phy clk
          if (!PHY_CLK)
            begin

               // Toggle clock while enabled
               if (!gate_tck)
                 TCK <= 1;

               // Read mode
               if (cmd[0])
                 begin
                    
                    // If reading back data
                    if ((state == pstate) && (state[2:0] == 3'b010) || (state[2:0] == 3'b101))
                      begin
                         
                         // Shift in on SHIFT-XX
                         din <= {TDO, din[BUF_SZ-1:1]};
                         ilen <= ilen + 1;
                                
                         // Check if we are done
                         if (!full && 
                             ((ctr == olen - 1) || 
                              ((olen > BUF_SZ) && (ilen == 6'(BUF_SZ - 1)))))
                           wren <= 1;
                  
                      end // if ((state == pstate) && (state[2:0] == 3'b010) || (state[2:0] == 3'b101))

                    // Clear write enable
                    if (wren)
                      wren <= 0;
                    // Coming out of pause flush (resp_blocked)
                    else if (!full && resp_blocked && (ilen == 0))
                      wren <= 1;

                 end // if (cmd[0])
               
            end // if (PHY_CLK)
          
          // Positive edge of PHY_CLK - setup data
          else
            begin

               // Toggle clock while enabled
               TCK <= 0;

               // Move to PAUSE-XX
               if (req_blocked || resp_blocked)
                 nstate[2:0] <= 3'b110;

               // Return from pause state
               if (state[2:0] == 3'b110)
                 begin
                    // If req blocked then clear busy for next read
                    if (req_blocked)                      
                      busy <= 0;

                    // Release blocked when OK
                    if (!full & resp_blocked)
                      resp_blocked <= 0;
                    if (req_blocked & dvalid)
                      req_blocked <= 0;

                    // If both are unblocked return to SHIFT-XX
                    if (!req_blocked & !resp_blocked)
                      nstate[2:0] <= 3'b010;
                 end

               // Shift out bits if in capture-XX state or EXIT1-XX state
               if (state[2:0] == 3'b010)
                 begin
                    
                    // Enter pause state
                    // No room for response
                    if (cmd[0] & full &
                        ((olen > BUF_SZ) && (ilen == 6'(BUF_SZ - 3))))
                      begin
                         // Set flag
                         resp_blocked <= 1;
                      end

                    // Do we need more data to send?
                    if (!cmd[1] &
                        (ctr != 0) & 
                        ((olen  - ctr) > BUF_SZ) &
                        ((ctr % BUF_SZ) == (BUF_SZ - 3)))
                      begin

                         // Nothing available - Enter pause state
                         if (empty)
                              // Set flag
                              req_blocked <= 1;
                         else
                           // Unblock for next transaction
                           busy <= 0;
                      end // if (!cmd[1] &...
                    
                    // Write data out
                    if (ctr < olen)
                      begin
                         
                         // Drive TDI
                         TDI <= dout[0];
                    
                         // Auto-extend if enabled
                         dout <= cmd[1] ? {dout[BUF_SZ-1], dout[BUF_SZ-1:1]} : {1'b0, dout[BUF_SZ-1:1]};
                         
                         // Increment counter
                         ctr <= ctr + 1;
                         
                      end // if ((ctr < olen) && !full)
                    // Clear TDI
                    else
                      TDI <= 0;

                    // Transition out two cycles early
                    if (ctr == olen - 2)
                      begin
                         // Move back to IDLE when done
                         nstate <= RUNTEST_IDLE;
                         busy <= 0;
                         pending <= 0;
                      end

                 end // if (state[2:0] == 3'b010)

               //
               // Latch in new command to shadow regs
               //
               if (rden)
                 begin
                    dvalid <= 1;
                 end
                     
               // If data is valid then latch into operating regs
               if (dvalid & !busy)
                 begin
                    cmd <= cmdp;
                    olen <= cmdp[0] ? olenp + 1 : olenp;
                    dout <= doutp;
                    dvalid <= 0;
                    busy <= 1;
                    
                    // Reset ctr, etc on new transaction
                    if (!pending)
                      begin

                         // Set to pending if not reset
                         pending <= 1;
                         
                         // Reset counter
                         ctr <= 0;

                         // Clear ilen
                         ilen <= 0;
                         din <= 0;
                    
                         // Move to RESET
                         if (olenp == 0)
                           nstate <= RUNTEST_IDLE;
                         // Move to SHIFT-IR
                         else if (cmdp[2])
                           nstate <= SHIFT_IR;
                         // Move to SHIFT-DR
                         else
                           nstate <= SHIFT_DR;
                      end // if (state[2:0] == 3'b000)
                    
                 end // if (dvalid & !busy)

               // Save previous state
               pstate <= state;               

               // Handle RESET/SWD -> JTAG switching
               // Override state machine
               if ((state == RUNTEST_IDLE) && (olen == 0) & pending)
                 begin
                         
                    // Sequence TMS on counter
                    case (ctr[6:0])
                      7'd8: if (cmd == 3'b110)
                        begin
                           pending <= 0;
                           busy <= 0;
                        end
                      7'd9:  TMS <= 1; // 50+ TMS=1
                      7'd17: if (cmd == 3'b000) TMS <= 0;
                      7'd18: if (cmd == 3'b000) // Handle normal RESET
                        begin
                           pending <= 0;
                           busy <= 0;
                        end
                      7'd69: TMS <= 0; // 2 TMS=0
                      7'd71: TMS <= 1; // 4 TMS=1
                      7'd75: TMS <= 0; // 2 TMS=0
                      7'd77: TMS <= 1; // 3 TMS=1
                      7'd80: TMS <= 0; // 2 TMS=0
                      7'd82: TMS <= 1; // 5+ TMS=1
                      7'd94: TMS <= 0; // Return to IDLE
                      7'd95: begin
                         pending <= 0;
                         busy <= 0;
                      end
                      default: ;
                    endcase // case (ctr[6:0])
                    
                    // Increment counter
                    ctr <= ctr + 1;
                    
                 end
               
               else
                 begin
                    
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
               
                 end // else: !if(state[2:0] == 3'b000)

            end // else: !if(PHY_CLK)
          
       end // else: !if(!RESETn)

endmodule // jtag_phy
