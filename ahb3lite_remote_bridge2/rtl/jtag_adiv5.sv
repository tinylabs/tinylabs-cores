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

`define PHY_CMD(_state, _cmd, _len, _dat, _done)  begin   \
   if (phy_wren) begin                                    \
      phy_wren <= 0;                                      \
      state <= _state;                                    \
      if (_done) busy <= 0;                               \
   end                                                    \
   else if (!phy_full) begin                              \
      phy_cmd <= _cmd;                                    \
      phy_olen <= _len;                                   \
      phy_dato <= {{29{1'b0}}, _dat};                     \
      phy_wren <= 1;                                      \
   end end

`define PHY_RSP(_state) begin                  \
   if (phy_dvalid) begin                       \
      state <= _state;                         \
   end end
       
// PHY commands
`define CMD_RESET          3'b000
`define CMD_SWITCH         3'b100
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

// Max number of retries
`define RETRY_MAX  5'h31

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
   jtag_phy u_phy
     (
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
   logic [7:0]              apsel;
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
                             IDLE = 0,
                             CMD,
                             IDCODE,
                             DPWRITE,
                             DPREAD,
                             APSEL,
                             APIRSEL,
                             APACCESS,
                             APBUF,
                             RESPONSE
                             } state_t;
   state_t state;
   
   
   // State machine logic
   always @(posedge CLK)
     if (~RESETn)
       begin
          state <= IDLE;
          dvalid <= 0;
          phy_dvalid <= 0;
          apsel <= -1;
       end
     else
       begin

          // Data valid one cycle after read
          if (rden)
            begin
               dvalid <= 1;
               busy <= 1;
            end
          else
            dvalid <= 0;

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
                   state <= CMD;
              end
            
            // Process command
            CMD:
              begin
                 // Execute command
                 casez ({addr[2:0], APnDP, RnW})
                   5'b00001: `PHY_CMD (IDCODE, `CMD_RESET, 0, 35'h0, 0)   // Emulated DP[0] read
                   5'b00101, 5'b01001, 5'b01101: `PHY_CMD (DPREAD, `CMD_IR_WRITE, 4, `IR_DPACC, 0)  // DPREAD
                   5'b0??00: `PHY_CMD (DPWRITE, `CMD_IR_WRITE, 4, `IR_DPACC, 0) // DPWRITE
                   5'b???11: `PHY_CMD (DPWRITE, `CMD_IR_WRITE, 4, `IR_DPACC, 0) // APREAD
                   5'b???10: `PHY_CMD (DPWRITE, `CMD_IR_WRITE, 4, `IR_DPACC, 0) // APWRITE
                   default:  state <= IDLE;
                   5'b10000: begin // DP[0x14]
                      if (dato[0])
                        `PHY_CMD (IDLE, `CMD_SWITCH, 0, 35'h0, 1)    
                      else
                        `PHY_CMD (IDLE, `CMD_RESET, 0, 35'h0, 1)
                   end
                   5'b10100: begin  // DP[0x14]
                      apsel <= dato[7:0];
                      state <= IDLE;
                      busy <= 0;
                   end
                 endcase // casez ({addr[2:0], APnDP, RnW})
              end
            
            // Read IDCODE
            IDCODE:   `PHY_CMD (RESPONSE, `CMD_DR_READ, 32, 35'h0, 0)

            // DP write
            DPWRITE:  `PHY_CMD (APnDP ? APSEL : IDLE, `CMD_DR_WRITE, 35, {dato, addr[1:0], 1'b0}, APnDP ? 0 : 1)
            
            // DP read
            DPREAD:   `PHY_CMD (RESPONSE, `CMD_DR_READ, 35, {32'h0, addr[1:0], 1'b1}, 1)
            
            // AP write   Write DP-SELECT, set APACC, Write AP
            APSEL:    `PHY_CMD (APIRSEL, `CMD_DR_WRITE, 35, {apsel, 16'h0, addr, 2'h0, addr[1:0], 1'b0}, 0)
            APIRSEL:  `PHY_CMD (APACCESS, `CMD_IR_WRITE, 4, `IR_APACC, 0)
            APACCESS: `PHY_CMD (RnW ? APBUF : IDLE, `CMD_DR_WRITE, 35, {dato, addr[1:0], RnW ? 1'b1 : 1'b0}, RnW ? 0 : 1) 
            
            // Read results from DP-RDBUFF
            APBUF:    `PHY_CMD (RESPONSE, `CMD_DR_READ, 35, {32'h0, addr[1:0], 1'b1}, 0)
            
            // Return response to client
            RESPONSE:
              if (phy_dvalid) 
                begin

                   // Anything but 010 is an ERROR
                   if (idcode || (phy_dati[31:29] == 3'b010))
                     stat <= 3'b100;
                   else
                     stat <= phy_dati[31:29];

                   // If past retries or response != WAIT return
                   // TODO: Clear FAULT error
                   if (idcode || (retries > `RETRY_MAX) || (phy_dati[31:29] == 3'b010))
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
