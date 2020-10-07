/**
 *  JTAG (Joint Test Action Group) PHY layer - Fully pipelined with
 *  async PHY_CLK
 * 
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */

module jtag_phy
  # (parameter MAX_CLEN = 1024,  // Max scan chain length
     parameter BUF_SZ   = 32,   // Data bits per FIFO packet
     // Derived
     parameter CMD_WIDTH = 2,
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
   typedef enum logic [1:0] {
                             CMD_NOP         = 0, // No shift operation
                             CMD_SHIFT_ONE   = 1, // Shift ones onto chain
                             CMD_SHIFT_ZERO  = 2, // Shift zeros onto chain
                             CMD_SHIFT_DATA  = 3  // Shift data onto chain
                             } cmd_t;
   
   // JTAG TAP state-machine
   // These states were chosen because bits[2:0] of each IR/DR
   // chain represent a 3bit LFSR (poly=6). Conveniently, bit[1]
   // also represents the TMS value required to get to the next
   // cycle. This should create a fast and small implementation.
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
   logic                           valid, busy;
   
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
   assign rden = !empty & !busy;
   
   always @(posedge PHY_CLK, negedge PHY_CLK)
     if (!RESETn | !ENABLE)
       begin
          busy <= 0;
          TCK <= 0;
          TMS <= 0;
          TDI <= 0;
          state <= RUNTEST_IDLE;
          nstate <= RUNTEST_IDLE;
          ctr <= 10'(MAX_CLEN - 1);
       end
     else // Not in RESET
       begin

          // Psitive edge of phy clk
          if (PHY_CLK)
            begin
               
               // Data valid next cycle after READ
               if (rden)
                 begin
                    valid <= 1;
                    busy <= 1;
                 end
               else
                 valid <= 0;
               
               // Copy to blocking regs
               if (valid)
                 begin
                    cmd <= cmdp;
                    olen <= olenp;
                    dout <= doutp;
                    nstate <= nstatep;
                    ctr <= 0;
                    ilen <= 0;
                 end

               // Toggle negative CLK edge
               TCK <= 0;
            end

          // Negative edge of PHY_CLK - setup data
          else
            begin

               // Transition cases to compliment
               // LFSR state machine. 
               // Only Exit1-XX -> Update-XX not handled as it seems
               // unnecessary
               if (busy)
                 begin

                    // Handle LOGIC_RESET/RUNTEST_IDLE
                    if (state[2:0] == 3'b000)
                      begin
                         if (nstate != state)
                           begin
                              TMS <= ~TMS;
                              state <= |state ? RUNTEST_IDLE : SELECT_DR;
                           end
                      end
                    
                    // Handle SELECT_DR -> SELECT_IR
                    else if ((state == SELECT_DR) & nstate[3])
                      state[3] <= 1;
                    
                    // Handle SELECT_IR -> LOGIC_RESET
                    else if ((state == SELECT_IR) && (nstate[2:0] == 3'b000))
                      begin
                         TMS <= 1;
                         state <= LOGIC_RESET;
                      end
                    
                    // Handle SHIFT_DR/IR PAUSE_DR/IR loops
                    else if ((state[1:0] == 2'b10) && (state[1:0] == nstate[1:0]))
                      ; // Do nothing
                    
                    // Handle skip of shift-IR/DR
                    else if ((state[2:0] == 3'b100) && (nstate[2:0] != 3'b010))
                      begin
                         TMS <= 1;
                         state[2:0] <= 3'b101; // Goto Exit1-DR/IR
                      end

                    // Handle transition from EXIT2-xx to SHIFT-xx
                    else if ((state[2:0] == 3'b111) && (nstate[2:0] == 3'b010))
                      begin
                         TMS <= 0;
                         state[2:0] <= 3'b010;
                      end

                    // Handle UPDATE-xx transition
                    else if (state[2:0] == 3'b011)
                      begin
                         // Clear MSB always
                         state[3] <= 0;
                         
                         // Switch back to IDLE if requested
                         if (nstate == RUNTEST_IDLE)
                           begin
                              TMS <= 0;
                              state <= RUNTEST_IDLE;
                           end                    
                      end
                    
                    // Drive state machine with LFSR
                    else
                      begin
                         state[1:0] <= state[2:1];
                         state[2] <= ^(state[2:0] & 3'h3);
                         TMS <= state[1];
                      end // else: !if(state[2:0] == 3'b111)
                    
                    // Once we reach our state increment counter until complete
                    if (state == nstate)
                      begin
                         if (ctr == olen)
                           begin
                              busy <= 0;
                              ctr <= 10'(MAX_CLEN - 1);
                              ilen <= ctr[$clog2(BUF_SZ):0];
                           end
                         else
                           ctr <= ctr + 1;

                         // Operate on command
                         case (cmd)
                           CMD_SHIFT_ZERO: TDI <= 0;
                           CMD_SHIFT_ONE:  TDI <= 1;                                                      
                           CMD_SHIFT_DATA:
                             begin
                                TDI <= dout[0];
                                dout <= {1'b0, dout[BUF_SZ-1:1]};
                             end
                           // Do nothing for nop
                           default: ;
                         endcase // case (cmd)

                         if (cmd != CMD_NOP)
                           begin
                              din[BUF_SZ-1] <= TDO;
                              din[BUF_SZ-2:0] <= din[BUF_SZ-1:1];
                           end
                      end

                    // Toggle positive CLK edge
                    TCK <= 1;

                 end // if (busy)

               // Set write enable when done
               if ((cmd != CMD_NOP) && (ctr == olen))
                 wren <= 1;
               else
                 wren <= 0;            

            end // else: !if(PHY_CLK)
          
       end // else: !if(!RESETn | !ENABLE)
   
   
endmodule // jtag_phy
