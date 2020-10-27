/**
 *  ARM ADIv5.2 debug interface for JTAG - Converts common FIFO interface to JTAG commands
 *
 *  Commands are passed via a FIFO. Input commands have the following format:
 *  [39:0] = DATA[31:0], ADDR[5:0], APnDP, RnW
 * 
 *  Responses are returned through a FIFO with the following format:
 *  [34:0] = DATA[31:0], STAT[2:0]
 * 
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 **/

// Local params
localparam CMD_WIDTH = 40;
localparam RESP_WIDTH = 35;

`define PHY_CMD(_state, _cmd, _len, _dat)  begin   \
   if (phy_wren) begin                             \
      phy_wren <= 0;                               \
      state <= _state;                             \
   end                                             \
   else if (!phy_full) begin                       \
      phy_cmd <= _cmd;                             \
      phy_olen <= _len;                            \
      phy_dato <= {{29{1'b0}}, _dat};              \
      phy_wren <= 1;                               \
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
`define RETRY_MAX  5'd31

module jtag_adiv5 # ( parameter FIFO_AW = 2 )
   (
    // Core signals
    input                   CLK,
    input                   PHY_CLK,
    input                   RESETn,
    input                   ENABLE,

    // FIFO interface in
    input [CMD_WIDTH-1:0]   WRDATA,
    input                   WREN,
    output                  WRFULL,

    // FIFO interface out
    output [RESP_WIDTH-1:0] RDDATA,
    input                   RDEN,
    output                  RDEMPTY,

    // JTAG signals
    output                  TCK,
    output                  TMS,
    output                  TDI,
    input                   TDO
    );

   // Command logic
   logic                    APnDP, RnW;
   logic [5:0]              addr;
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
           .DATA_WIDTH  (CMD_WIDTH)
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
           .DATA_WIDTH  (RESP_WIDTH)
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
   logic [63:0]             phy_dato, phy_dati;
   logic [11:0]             phy_olen;
   logic [5:0]              phy_ilen;
   logic [2:0]              phy_cmd;
   logic                    phy_wren, phy_rden, phy_empty, phy_full, phy_dvalid;
   
   // Underlying PHY
   jtag_phy # (.FIFO_AW (FIFO_AW + 1))
     u_phy (
      .CLK      (CLK),
      .PHY_CLK  (PHY_CLK),
      .RESETn   (RESETn),
      .ENABLE   (ENABLE),

      // FIFO in
      .WRDATA  ({phy_dato, phy_olen, phy_cmd}),
      .WREN    (phy_wren),
      .WRFULL  (phy_full),
      
      // FIFO out
      .RDDATA  ({phy_dati, phy_ilen}),
      .RDEN    (phy_rden),
      .RDEMPTY (phy_empty),

      // JTAG signals
      .TCK     (TCK),
      .TMS     (TMS),
      .TDI     (TDI),
      .TDO     (TDO)
      );

   // AP selected
   logic [4:0]              retries;
   logic                    idcode;

   // Are we responding to IDCODE
   assign idcode = ((phy_cmd == `CMD_DR_READ) && (addr == 0) && !APnDP);
   
   // Combinatorial logic
   assign rden = !empty & !busy;

   // Read PHY as soon as available
   assign phy_rden = !phy_empty;

   // State machine
   typedef enum logic [3:0] {
                             IDLE       = 0,
                             CMD        = 1,
                             IDCODE     = 2,
                             DPWRITE    = 3,
                             DPREAD     = 4,
                             APACCESS   = 5,
                             FLUSH      = 6,
                             CHECK      = 7,
                             RESPONSE   = 8,
                             ABORT_IR   = 9,
                             ABORT      = 10,
                             ABORT_DONE = 11,
                             RESET_DONE = 12
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
          if (phy_rden)
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
                   end
              end
            
            // Process command
            CMD:
              begin
                 // Execute command
                 casez ({addr[1:0], APnDP, RnW})
                   default:  state <= IDLE;
                   4'b0101: `PHY_CMD (DPREAD, `CMD_IR_WRITE, 4, `IR_DPACC)   // READ DP[4]
                   4'b1?01: `PHY_CMD (DPREAD, `CMD_IR_WRITE, 4, `IR_DPACC)   // READ DP[8/C]
                   4'b0?00: `PHY_CMD (DPWRITE, `CMD_IR_WRITE, 4, `IR_DPACC)  // WRITE DP[0/4/8]
                   4'b1000: `PHY_CMD (DPWRITE, `CMD_IR_WRITE, 4, `IR_DPACC)  // WRITE DP[8]
                   4'b??1?: `PHY_CMD (APACCESS, `CMD_IR_WRITE, 4, `IR_APACC) // READ/WRITE AP
                   // Pseudo DP registers
                   // DP[0]    read - emulate IDCODE found on SWD interface
                   // DP[0xc] write - Handle RESET/line switch
                   4'b0001: `PHY_CMD (IDCODE, `CMD_RESET, 0, 35'h0) // Read DP[0]
                   4'b1100: begin                                   // Write DP[0xc]
                      if (dato[0])
                        `PHY_CMD (RESET_DONE, `CMD_SWITCH, 0, 35'h0)
                      else
                        `PHY_CMD (RESET_DONE, `CMD_RESET, 0, 35'h0)
                   end
                 endcase // casez ({addr[1:0], APnDP, RnW})
              end

            // Done return to IDLE
            RESET_DONE:
              begin
                 busy <= 0;
                 state <= IDLE;
              end
            
            // Read IDCODE
            IDCODE:   `PHY_CMD (RESPONSE, `CMD_DR_READ, 32, 35'h0)

            // DP write
            DPWRITE:  `PHY_CMD (CHECK, `CMD_DR_WRITE, 35, {dato, addr[1:0], 1'b0})
            
            // DP read
            DPREAD:   `PHY_CMD (CHECK, `CMD_DR_WRITE, 35, {32'h0, addr[1:0], 1'b1})

            // AP access
            APACCESS: `PHY_CMD (FLUSH, `CMD_DR_WRITE, 35, {dato, addr[1:0], RnW})

            // Flush AP write
            FLUSH:    `PHY_CMD (CHECK, `CMD_FLUSH, 0, 35'h0)
            
            // Flush DR to check operation
            CHECK:    `PHY_CMD (RESPONSE, `CMD_DR_READ, 35, 35'h7)

            // Set ABORT IR
            ABORT_IR: `PHY_CMD (ABORT, `CMD_IR_WRITE, 4, `IR_ABORT)

            // Write ABORT - Return to IDLE
            ABORT:    `PHY_CMD (ABORT_DONE, `CMD_DR_WRITE, 35, 35'hf8)

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
                   if (idcode || (phy_dati[31:29] == 3'b010))
                     stat <= 3'b100;
                   else // Translate to SWD wait or FAULT
                     stat <= (phy_dati[31:29] == 3'b001) ? 3'b010 : 3'b001;

                   // If past retries or response != WAIT return
                   if (retries == `RETRY_MAX)
                     state <= ABORT_IR;
                   
                   // Response OK - return
                   else if (idcode || (phy_dati[31:29] == 3'b010))
                     begin
                       // Copy data back
                       dati <= phy_dati[63:32];
                       
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
