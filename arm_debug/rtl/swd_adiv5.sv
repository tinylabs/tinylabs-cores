/**
 *  ARM ADIv5.2 debug interface for SWD - Converts common FIFO interface to SWD commands
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

// Get command interface
import adiv5_pkg::*;


`define PHY_RAW(_state, _len, _t0, _t1, _dat)  begin  \
   if (PHY_WREN) begin                                \
      PHY_WREN <= 0;                                  \
      state <= _state;                                \
   end                                                \
   else if (!PHY_WRFULL) begin                        \
      PHY_WRDATA <= {_len, _t0, _t1, _dat};           \
      PHY_WREN <= 1;                                  \
   end end

`define PHY_READ(_state)  `PHY_RAW(_state, 6'd46, 6'd8, 6'd45, {21'h0, phy_cmd})
`define PHY_WRITE(_state) `PHY_RAW(_state, 6'd46, 6'd8, 6'd12, {21'h0, phy_cmd})
 
`define PHY_RSP(_state) begin                  \
   if (phy_dvalid) begin                       \
      state <= _state;                         \
   end end
       
// Max number of retries
`define RETRY_MAX  4'd15

module swd_adiv5 #(
                   parameter FIFO_AW = 2
                   )
   (
    // Core signals
    input                            CLK,
    input                            RESETn,

    // CMD interface
    input [ADIv5_CMD_WIDTH-1:0]      WRDATA,
    input                            WREN,
    output                           WRFULL,
    output [ADIv5_RESP_WIDTH-1:0]    RDDATA,
    input                            RDEN,
    output                           RDEMPTY,

    // PHY interface
    output logic [SWD_CMD_WIDTH-1:0] PHY_WRDATA,
    output logic                     PHY_WREN,
    input                            PHY_WRFULL,
    input [SWD_RESP_WIDTH-1:0]       PHY_RDDATA,
    output logic                     PHY_RDEN,
    input                            PHY_RDEMPTY
    );

   // Command logic
   logic                    APnDP, APnDPp, RnW;
   logic [1:0]              addr, addrp;
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
             .rd_data_o ({dato, addrp, APnDPp, RnW}),
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
   logic [42:0]             phy_cmd;
   logic [2:0]              phy_resp;
   
   //               turn, dparity, data, turn, park, stop, cmd parity,         addr, RnW, APnDP, start
   assign phy_cmd = {1'b0, ^dato, dato, 1'b0, 1'b1, 1'b0, ^{addr, RnW, APnDP}, addr, RnW, APnDP, 1'b1};
   
   // AP selected
   logic [3:0]              retries;

   // Combinatorial logic
   assign rden = !empty & !busy;

   // Read PHY as soon as available
   assign PHY_RDEN = !PHY_RDEMPTY;

   // Response from phy
   assign phy_resp = RnW ? PHY_RDDATA[41:39] : PHY_RDDATA[8:6];
   
   // State machine
   typedef enum logic [2:0] {
                             IDLE     = 0,
                             CMD      = 1,
                             SWITCH   = 2,
                             RESET2   = 3,
                             FLUSH    = 4,
                             RESPONSE = 5,
                             IGNORE   = 6,
                             DONE     = 7
                             } state_t;
   state_t state;
   
   
   // State machine logic
   always @(posedge CLK)
     if (~RESETn)
       begin
          state <= IDLE;
          dvalid <= 0;
          phy_dvalid <= 0;
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
                      state <= CMD;
                      dvalid <= 0;
                      addr <= addrp;
                      APnDP <= APnDPp;
                   end
              end
            
            // Process command
            CMD:
              begin
                 // Execute command
                 casez ({addr, APnDP, RnW})
                   default:  state <= IDLE;
                   4'b??11: `PHY_READ  (RESPONSE) // AP READ
                   4'b??01: `PHY_READ  (RESPONSE) // DP READ
                   4'b??10: `PHY_WRITE (FLUSH)    // AP WRITE
                   4'b1000: `PHY_WRITE (RESPONSE) // DP WRITE [8]
                   4'b0?00: `PHY_WRITE (RESPONSE) // DP WRITE [0/4]
                   // Pseudo DP registers
                   // DP[0x10] write - Handle RESET/protocol switch
                   4'b1100: begin
                      if (dato[0])
                        `PHY_RAW (SWITCH, 6'd60, 6'd63, 6'd63, {64{1'b1}})
                      else
                        `PHY_RAW (DONE, 6'd60, 6'd63, 6'd63, {64{1'b1}})
                   end
                 endcase // casez ({addr, APnDP, RnW})
              end

            // Switch to SWD
            SWITCH:  `PHY_RAW (RESET2, 6'd16, 6'd63, 6'd63, {48'h0, 16'he79e})

            // Do additional line reset
            RESET2:  `PHY_RAW (DONE, 6'd62, 6'd63, 6'd63, {10'h0, {54{1'b1}}})

            // Flush after AP write
            FLUSH:   `PHY_RAW (RESPONSE, 6'd8, 6'd63, 6'd63, 64'h0)

            // Finished - return to IDLE
            DONE:
              begin
                 busy <= 0;
                 state <= IDLE;
              end

            // Return response to client
            RESPONSE:
              if (phy_dvalid) 
                begin
                   
                   // Retries exceeded - Issue ABORT
                   if (retries == `RETRY_MAX)
                     `PHY_RAW (IGNORE, 6'd46, 6'd8, 6'd12, 64'h20000003EA1) 
                   // Response OK and parity OK on READ
                   else if ((phy_resp == 3'b100) && ((^PHY_RDDATA[38:7] == PHY_RDDATA[6]) | ~RnW))
                     begin

                        // If AP read move to read DP[0xc]
                        if (APnDP & RnW)
                          begin  // Read RDBUF (DP[0xC]
                             addr <= 3;
                             APnDP <= 0;
                             state <= CMD;                             
                          end
                        // Done return results
                        else
                          begin
                             // Copy data/status
                             dati <= {<<{PHY_RDDATA[38:7]}};
                             stat <= phy_resp;
                        
                             // Write to FIFO, return to IDLE
                             state <= IDLE;
                             wren <= 1;
                             busy <= 0;
                          end
                     end
                   else 
                     begin // Retry transaction                        
                        state <= CMD;
                        retries <= retries + 1;
                     end
                   
                end // if (phy_dvalid)

            // Recover from ABORT - return to IDLE
            IGNORE:
              if (phy_dvalid)
                begin
                   state <= IDLE;
                   stat <= 3'b001; // Return FAULT
                   dati <= 0;
                   wren <= 1;
                   busy <= 0;
                end
                    
          endcase // case (state)               
          
       end // else: !if(~RESETn)
   
endmodule // swd_adiv5
