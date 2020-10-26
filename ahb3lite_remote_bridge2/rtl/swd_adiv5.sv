/**
 *  ARM ADIv5.2 debug interface for SWD - Converts common FIFO interface to SWD commands
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

`define PHY_RAW(_state, _len, _t0, _t1, _dat, _done)  begin  \
   if (phy_wren) begin                                       \
      phy_wren <= 0;                                         \
      state <= _state;                                       \
      if (_done) busy <= 0;                                  \
   end                                                       \
   else if (!phy_full) begin                                 \
      phy_olen <= _len;                                      \
      phy_t0 <= _t0;                                         \
      phy_t1 <= _t1;                                         \
      phy_dato <= _dat;                                      \
      phy_wren <= 1;                                         \
   end end

`define PHY_READ(_state, _done)  `PHY_RAW(_state, 46, 8, 45, {21'h0, phy_cmd}, _done)
`define PHY_WRITE(_state, _done) `PHY_RAW(_state, 46, 8, 12, {21'h0, phy_cmd}, _done)
 
`define PHY_RSP(_state) begin                  \
   if (phy_dvalid) begin                       \
      state <= _state;                         \
   end end
       
// Max number of retries
`define RETRY_MAX  5'h31

module swd_adiv5 # ( parameter FIFO_AW = 2 )
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

    // SWD signals
    output                  TCK,
    output                  TMSOUT,
    input                   TMSIN,
    output                  TMSOE
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
   logic [63:0]             phy_dato;
   logic [36:0]             phy_dati;
   logic [5:0]              phy_olen, phy_ilen;
   logic [5:0]              phy_t0, phy_t1;
   logic                    phy_wren, phy_rden, phy_empty, phy_full, phy_dvalid;
   logic [42:0]             phy_cmd;
   logic [2:0]              phy_resp;
   
   //               turn, dparity, data, turn, park, stop, cmd parity,               addr[1:0], RnW, APnDP, start
   assign phy_cmd = {1'b0, ^dato, dato, 1'b0, 1'b1, 1'b0, ^{addr[1:0], RnW, APnDP}, addr[1:0], RnW, APnDP, 1'b1};
   
   // Underlying PHY
   swd_phy u_phy
     (
      .CLK      (CLK),
      .PHY_CLK  (PHY_CLK),
      .RESETn   (RESETn),
      .ENABLE   (ENABLE),

      // FIFO in
      .WRDATA  ({phy_olen, phy_t0, phy_t1, phy_dato}),
      .WREN    (phy_wren),
      .WRFULL  (phy_full),
      
      // FIFO out
      .RDDATA  ({phy_dati, phy_ilen}),
      .RDEN    (phy_rden),
      .RDEMPTY (phy_empty),

      // SWD signals
      .SWDCLK  (TCK),
      .SWDIN   (TMSIN),
      .SWDOUT  (TMSOUT),
      .SWDOE   (TMSOE)
      );

   // AP selected
   logic [4:0]              retries;

   // Combinatorial logic
   assign rden = !empty & !busy;

   // Read PHY as soon as available
   assign phy_rden = !phy_empty;

   // Response from phy
   assign phy_resp = RnW ? phy_dati[35:33] : phy_dati[2:0];
   
   // State machine
   typedef enum logic [2:0] {
                             IDLE     = 0,
                             CMD      = 1,
                             SWITCH   = 2,
                             RESET2   = 3,
                             FLUSH    = 4,
                             RESPONSE = 5
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
                 casez ({addr[2:0], APnDP, RnW})
                   default:  state <= IDLE;
                   5'b0???1: `PHY_READ (RESPONSE, 1)  // READ
                   5'b0??10: `PHY_WRITE (FLUSH, 0)    // AP WRITE
                   5'b0??00: `PHY_WRITE (RESPONSE, 1) // DP WRITE
                   // Pseudo DP registers
                   // DP[0x10] write - Handle RESET/protocol switch
                   5'b10000: begin
                      if (dato[0])
                        `PHY_RAW (SWITCH, 60, 63, 63, {64{1'b1}}, 0)
                      else
                        `PHY_RAW (IDLE, 60, 63, 63, {64{1'b1}}, 1)
                   end
                 endcase // casez ({addr[2:0], APnDP, RnW})
              end

            // Switch to SWD
            SWITCH:  `PHY_RAW (RESET2, 16, 63, 63, {48'h0, 16'he79e}, 0)

            // Do additional line reset
            RESET2:  `PHY_RAW (IDLE, 62, 63, 63, {10'h0, {54{1'b1}}}, 1)

            // Flush after AP write
            FLUSH:   `PHY_RAW (RESPONSE, 8, 63, 63, 64'h0, 1)
            
            // Return response to client
            RESPONSE:
              if (phy_dvalid) 
                begin

                   // If past retries or response != WAIT return
                   // TODO: Clear FAULT error
                   if ((retries > `RETRY_MAX) || (phy_resp == 3'b100))
                     begin
                        // Copy data/status
                        dati <= {<<{phy_dati[32:1]}};
                        stat <= phy_resp;
                   
                        // Check parity @ phy_dati[0]
                        // Check length
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
   
endmodule; // swd_adiv5
