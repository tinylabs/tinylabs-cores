/**
 *  ARM ADIv5.2 debug interface for JTAG - Converts common FIFO interface to JTAG commands
 *
 *  Commands are passed via a FIFO. Input commands have the following format:
 *  [39:0] = DATA[31:0], ADDR[1:0], APnDP, RnW
 * 
 *  Responses are returned through a FIFO with the following format:
 *  [34:0] = DATA[31:0], STAT[2:0]
 * 
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 **/

`define PHY_CMD(_state, _cmd, _len, _dat)  begin       \
   if (PHY_WREN) begin                                 \
      PHY_WREN <= 0;                                   \
      state <= _state;                                 \
   end                                                 \
   else if (!PHY_WRFULL) begin                         \
      PHY_WRDATA <= {{{29{1'b0}}, _dat}, _len, _cmd};  \
      PHY_WREN <= 1;                                   \
   end end

`define PHY_RSP(_state) begin                  \
   if (phy_dvalid) begin                       \
      state <= _state;                         \
   end end
       
// PHY commands
`define CMD_RESET          3'b000
`define CMD_SWITCH         3'b100
`define CMD_FLUSH          3'b110
`define CMD_DR_WRITE       3'b000
`define CMD_DR_READ        3'b001
`define CMD_DR_WRITE_AUTO  3'b010
`define CMD_DR_READ_AUTO   3'b011
`define CMD_IR_WRITE       3'b100
`define CMD_IR_READ        3'b101
`define CMD_IR_WRITE_AUTO  3'b110
`define CMD_IR_READ_AUTO   3'b111

// IR registers
`define IR_DPACC  35'hA
`define IR_APACC  35'hB
`define IR_ABORT  35'h8

// Max number of retries
`define RETRY_MAX  4'd15

module jtag_adiv5 #(
                    parameter FIFO_AW = 2,
                    parameter ADIv5_CMD_WIDTH = 36,
                    parameter ADIv5_RESP_WIDTH = 35
                    )
   (
    // Core signals
    input                             CLK,
    input                             RESETn,

    // CMD interface
    input [ADIv5_CMD_WIDTH-1:0]       WRDATA,
    input                             WREN,
    output                            WRFULL,
    output [ADIv5_RESP_WIDTH-1:0]     RDDATA,
    input                             RDEN,
    output                            RDEMPTY,

    // PHY interface
    output logic [JTAG_CMD_WIDTH-1:0] PHY_WRDATA,
    output logic                      PHY_WREN,
    input                             PHY_WRFULL,
    input [JTAG_RESP_WIDTH-1:0]       PHY_RDDATA,
    output logic                      PHY_RDEN,
    input                             PHY_RDEMPTY
    );

   // Command logic
   logic                    APnDP, RnW;
   logic [1:0]              addr;
   logic [31:0]             dato;

   // Response logic
   logic [2:0]              stat;
   logic [31:0]             dati;

   // FIFO logic
   logic                    rden, wren, full, empty;
   logic                    busy, dvalid;
   
   // Create FIFOs to pass commands
   fifo # (
           .DEPTH_WIDTH (FIFO_AW),
           .DATA_WIDTH  (ADIv5_CMD_WIDTH)
           )
   u_cmd_in (
             .clk       (CLK),
             .rst       (~RESETn),
             .wr_data_i (WRDATA),
             .wr_en_i   (WREN),
             .full_o    (WRFULL),
             .rd_data_o ({dato, addr, APnDP, RnW}),
             .rd_en_i   (rden),
             .empty_o   (empty)
             );
   fifo # (
           .DEPTH_WIDTH (FIFO_AW),
           .DATA_WIDTH  (ADIv5_RESP_WIDTH)
           )
   u_resp_out (
               .clk       (CLK),
               .rst       (~RESETn),
               .rd_data_o (RDDATA),
               .rd_en_i   (RDEN),
               .empty_o   (RDEMPTY),
               .wr_data_i ({dati, stat}),
               .wr_en_i   (wren),
               .full_o    (full)
               );

   // Phy logic
   logic                    phy_dvalid;

   // Internal logic
   logic [3:0]              retries;
   logic [3:0]              ir;   // IR cache
   logic                    idcode;
              
   // Are we responding to IDCODE
   assign idcode = ((PHY_WRDATA[2:0] == `CMD_DR_READ) && (addr == 0) && !APnDP);
   
   // Combinatorial logic
   assign rden = !empty & !busy;

   // Read PHY as soon as available
   assign PHY_RDEN = !PHY_RDEMPTY;

   // State machine
   typedef enum logic [3:0] {
                             IDLE       = 0,
                             SET_IR     = 1,
                             SAVE_IR    = 2,
                             CMD        = 3,
                             IDCODE     = 4,
                             DPWRITE    = 5,
                             DPREAD     = 6,
                             APACCESS   = 7,
                             FLUSH      = 8,
                             CHECK      = 9,
                             RESPONSE   = 10,
                             ABORT_IR   = 11,
                             ABORT      = 12,
                             ABORT_DONE = 13,
                             RESET_DONE = 14
                             } state_t;
   state_t state;
   
   
   // State machine logic
   always @(posedge CLK)
     if (~RESETn)
       begin
          state <= IDLE;
          dvalid <= 0;
          phy_dvalid <= 0;
          ir <= 4'hf;
       end
     else
       begin

          // Data valid one cycle after read
          if (rden)
            begin
               dvalid <= 1;
               busy <= 1;
            end

          // PHY data available one cycle after read
          if (PHY_RDEN)
            phy_dvalid <= 1;
          else
            phy_dvalid <= 0;
          
          // State machine
          case (state)
            
            default: state <= IDLE; // Shouldn't get here
               
            // Clear wren/busy
            IDLE: 
              begin
                 wren <= 0;
                 retries <= 0;
                 
                 // Latch in command
                 if (dvalid)
                   begin
                      casez ({addr, APnDP, RnW})
                        default:  state <= SET_IR;
                        4'b0001, 4'b1100: state <= CMD;
                      endcase // casez ({addr, APnDP, RnW})
                      dvalid <= 0;
                   end
              end

            // Set IR
            SET_IR:
              begin
                 // Set IR if not same as cache
                 if (APnDP && (ir != 4'hB))
                   `PHY_CMD (SAVE_IR, `CMD_IR_WRITE, 12'd4, `IR_APACC)
                 else if (!APnDP && (ir != 4'hA))
                   `PHY_CMD (SAVE_IR, `CMD_IR_WRITE, 12'd4, `IR_DPACC)
                 else
                   state <= CMD;
              end

            // Save IR and process cmd
            SAVE_IR:
              begin
                 ir <= APnDP ? 4'hB : 4'hA;
                 state <= CMD;
              end
            
            // Process command
            CMD:
              begin
                 // Execute command
                 casez ({addr, APnDP, RnW})
                   default:  state <= IDLE;
                   4'b0101, 4'b1?01: state <= DPREAD;   // READ DP[4/8/C]
                   4'b1000, 4'b0?00: state <= DPWRITE;  // WRITE DP[0/4/8]
                   4'b??1?: state <= APACCESS;          // READ/WRITE AP
                   // Pseudo DP registers
                   // DP[0]    read - emulate IDCODE found on SWD interface
                   // DP[0xc] write - Handle RESET/line switch
                   4'b0001: `PHY_CMD (IDCODE, `CMD_RESET, 12'd0, 35'h0) // Read DP[0]
                   4'b1100: begin                                   // Write DP[0xc]
                      if (dato[0])
                        `PHY_CMD (RESET_DONE, `CMD_SWITCH, 12'd0, 35'h0)
                      else
                        `PHY_CMD (RESET_DONE, `CMD_RESET, 12'd0, 35'h0)
                   end
                 endcase // casez ({addr, APnDP, RnW})
              end

            // Done return to IDLE
            RESET_DONE:
              begin
                 busy <= 0;
                 state <= IDLE;
              end
            
            // Read IDCODE
            IDCODE:   `PHY_CMD (RESPONSE, `CMD_DR_READ, 12'd32, 35'h0)

            // DP write
            DPWRITE:  `PHY_CMD (CHECK, `CMD_DR_WRITE, 12'd35, {dato, addr, 1'b0})
            
            // DP read
            DPREAD:   `PHY_CMD (CHECK, `CMD_DR_WRITE, 12'd35, {32'h0, addr, 1'b1})

            // AP access
            APACCESS: `PHY_CMD (FLUSH, `CMD_DR_WRITE, 12'd35, {dato, addr, RnW})

            // Flush AP write
            FLUSH:    `PHY_CMD (CHECK, `CMD_FLUSH, 12'd0, 35'h0)
            
            // Flush DR to check operation
            CHECK:    `PHY_CMD (RESPONSE, `CMD_DR_READ, 12'd35, 35'h7)

            // Set ABORT IR
            ABORT_IR: `PHY_CMD (ABORT, `CMD_IR_WRITE, 12'd4, `IR_ABORT)

            // Write ABORT - Return to IDLE
            ABORT:    `PHY_CMD (ABORT_DONE, `CMD_DR_WRITE, 12'd35, 35'hf8)

            // Cleanup and return response
            ABORT_DONE:
              begin
                 state <= IDLE;
                 stat <= 3'b001;
                 wren <= 1;
                 busy <= 0;
              end

            // Return response to client
            RESPONSE:
              if (phy_dvalid) 
                begin

                   // Anything but 010 is an ERROR
                   if (idcode || (PHY_RDDATA[37:35] == 3'b010))
                     stat <= 3'b100;
                   else // Translate to SWD wait or FAULT
                     stat <= (PHY_RDDATA[37:35] == 3'b001) ? 3'b010 : 3'b001;

                   // If past retries or response != WAIT return
                   if (retries == `RETRY_MAX)
                     state <= ABORT_IR;
                   
                   // Response OK - return
                   else if (idcode || (PHY_RDDATA[37:35] == 3'b010))
                     begin
                       // Copy data back
                       dati <= PHY_RDDATA[69:38];
                       
                        // Write to FIFO, return to IDLE
                       state <= IDLE;
                       wren <= 1;
                       busy <= 0;
                     end
                   else 
                     begin // Retry transaction
                        state <= CMD;
                        retries <= retries + 1;
                     end
                   
                end // if (phy_dvalid)
            
          endcase // case (state)               
          
       end // else: !if(~RESETn)
   
endmodule; // jtag_adiv5
