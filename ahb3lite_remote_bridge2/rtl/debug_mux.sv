/**
 *  MUX two ADIv5 cores and provide direct access to jtag_phy
 * 
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */
localparam ADIv5_CMD_WIDTH  = 36;
localparam ADIv5_RESP_WIDTH = 35;
//localparam JTAG_CMD_WIDTH   = 79;
//localparam JTAG_RESP_WIDTH  = 70;
//localparam SWD_CMD_WIDTH    = 82;
//localparam SWD_RESP_WIDTH   = 43;

module debug_mux #( parameter FIFO_AW = 2 )
   (
    // System clock and reset
    input                               CLK,
    input                               RESETn,
    // PHY clock
    input                               PHY_CLK,
    input                               PHY_CLKn,
    // Select interface
    input                               JTAGnSWD,
    // Select direct JTAG PHY interface
    input                               JTAG_DIRECT,
    // ADIv5 FIFO interface
    input [ADIv5_CMD_WIDTH-1:0]         ADIv5_WRDATA,
    input                               ADIv5_WREN,
    output logic                        ADIv5_WRFULL,
    output logic [ADIv5_RESP_WIDTH-1:0] ADIv5_RDDATA,
    input                               ADIv5_RDEN,
    output logic                        ADIv5_RDEMPTY,
    // JTAG direct PHY FIFO interface
    input [JTAG_CMD_WIDTH-1:0]          JTAG_WRDATA,
    input                               JTAG_WREN,
    output                              JTAG_WRFULL,
    output [JTAG_RESP_WIDTH-1:0]        JTAG_RDDATA,
    input                               JTAG_RDEN,
    output                              JTAG_RDEMPTY, 
    // PHY signals
    output logic                        TCK,
    output logic                        TDI,
    output logic                        TMSOUT,
    output logic                        TMSOE,
    input                               TMSIN,
    input                               TDO
    );

   // Internal ADIv5 signals
   logic                                jtag_adiv5_WRFULL, swd_adiv5_WRFULL;
   logic                                jtag_adiv5_RDEMPTY, swd_adiv5_RDEMPTY;
   logic [ADIv5_RESP_WIDTH-1:0]         jtag_adiv5_RDDATA, swd_adiv5_RDDATA;

   // Internal PHY interface
   logic [SWD_CMD_WIDTH-1:0]            swd_WRDATA;
   logic [SWD_RESP_WIDTH-1:0]           swd_RDDATA;
   logic                                swd_WREN, swd_RDEN, swd_WRFULL, swd_RDEMPTY;
   logic [JTAG_CMD_WIDTH-1:0]           jtag_WRDATA;
   logic [JTAG_RESP_WIDTH-1:0]          jtag_RDDATA;
   logic                                jtag_WREN, jtag_RDEN, jtag_WRFULL, jtag_RDEMPTY;

   // JTAG phy signals
   logic [JTAG_CMD_WIDTH-1:0]           jtag_phy_WRDATA;
   logic [JTAG_RESP_WIDTH-1:0]          jtag_phy_RDDATA;
   logic                                jtag_phy_WREN, jtag_phy_RDEN, jtag_phy_WRFULL, jtag_phy_RDEMPTY;

   // Internal phy signals
   logic                                jtag_TCK, jtag_TMS, jtag_TDI;
   logic                                swd_TCK, swd_TMSOUT, swd_TMSOE;

   
   // MUX hardware signals
   assign TCK = JTAGnSWD | JTAG_DIRECT ? jtag_TCK : swd_TCK;
   assign TDI = JTAGnSWD | JTAG_DIRECT ? jtag_TDI : 1'b0;
   assign TMSOUT = JTAGnSWD | JTAG_DIRECT ? jtag_TMS : swd_TMSOUT;
   assign TMSOE = JTAGnSWD | JTAG_DIRECT ? 1'b1 : swd_TMSOE;

   // MUX ADIv5 interface
   assign ADIv5_WRFULL = JTAGnSWD ? jtag_adiv5_WRFULL : swd_adiv5_WRFULL;
   assign ADIv5_RDDATA = JTAGnSWD ? jtag_adiv5_RDDATA : swd_adiv5_RDDATA;
   assign ADIv5_RDEMPTY = JTAGnSWD ? jtag_adiv5_RDEMPTY : swd_adiv5_RDEMPTY;

   
   // Mux ADIv5 / JTAG DIRECT
   assign jtag_phy_WRDATA = JTAG_DIRECT ? JTAG_WRDATA : jtag_WRDATA;
   assign jtag_phy_WREN   = JTAG_DIRECT ? JTAG_WREN   : jtag_WREN;
   assign jtag_phy_RDEN   = JTAG_DIRECT ? JTAG_RDEN   : jtag_RDEN;
   // Route to external interface of ADIv5
   assign JTAG_WRFULL     = JTAG_DIRECT ? jtag_phy_WRFULL : 1'b0;
   assign JTAG_RDDATA     = JTAG_DIRECT ? jtag_phy_RDDATA : 0;
   assign JTAG_RDEMPTY    = JTAG_DIRECT ? jtag_phy_RDEMPTY : 1'b1;
   assign jtag_WRFULL     = JTAG_DIRECT ? 1'b0 : jtag_phy_WRFULL;
   assign jtag_RDDATA     = JTAG_DIRECT ? 0 : jtag_phy_RDDATA;
   assign jtag_RDEMPTY    = JTAG_DIRECT ? 1'b1 : jtag_phy_RDEMPTY;
             
   // Instantiate JTAG phy
   jtag_phy #(.FIFO_AW (FIFO_AW + 1))
   u_jtag_phy (
               .CLK      (CLK),
               .PHY_CLK  (PHY_CLK),
               .PHY_CLKn (PHY_CLKn),
               .RESETn   (RESETn & (JTAGnSWD | JTAG_DIRECT)),
               .WRDATA   (jtag_phy_WRDATA),
               .WREN     (jtag_phy_WREN),
               .WRFULL   (jtag_phy_WRFULL),
               .RDDATA   (jtag_phy_RDDATA),
               .RDEN     (jtag_phy_RDEN),
               .RDEMPTY  (jtag_phy_RDEMPTY),
               .TCK      (jtag_TCK),
               .TMS      (jtag_TMS),
               .TDI      (jtag_TDI),
               .TDO      (TDO)
               );
   
   // Instantiate SWD phy
   swd_phy #(.FIFO_AW (FIFO_AW))
   u_swd_phy (
              .CLK      (CLK),
              .PHY_CLK  (PHY_CLK),
              .PHY_CLKn (PHY_CLKn),
              .RESETn   (RESETn & ~JTAGnSWD & ~JTAG_DIRECT),
              .WRDATA   (swd_WRDATA),
              .WREN     (swd_WREN),
              .WRFULL   (swd_WRFULL),
              .RDDATA   (swd_RDDATA),
              .RDEN     (swd_RDEN),
              .RDEMPTY  (swd_RDEMPTY),
              .SWDCLK   (swd_TCK),
              .SWDIN    (TMSIN),
              .SWDOUT   (swd_TMSOUT),
              .SWDOE    (swd_TMSOE)
              );

   // Instantiate JTAG ADIv5
   jtag_adiv5 #(.FIFO_AW (FIFO_AW))
   u_jtag_adiv5 (
                 .CLK         (CLK),
                 .RESETn      (RESETn & JTAGnSWD),
                 .WRDATA      (ADIv5_WRDATA),
                 .WREN        (ADIv5_WREN),
                 .WRFULL      (jtag_adiv5_WRFULL),
                 .RDDATA      (jtag_adiv5_RDDATA),
                 .RDEN        (ADIv5_RDEN),
                 .RDEMPTY     (jtag_adiv5_RDEMPTY),
                 .PHY_WRDATA  (jtag_WRDATA),
                 .PHY_WREN    (jtag_WREN),
                 .PHY_WRFULL  (jtag_WRFULL),
                 .PHY_RDDATA  (jtag_RDDATA),
                 .PHY_RDEN    (jtag_RDEN),
                 .PHY_RDEMPTY (jtag_RDEMPTY)
                 );
   
   // Instantiate SWD ADIv5
   swd_adiv5 #(.FIFO_AW (FIFO_AW + 1))
   u_swd_adiv5 (
                .CLK         (CLK),
                .RESETn      (RESETn & ~JTAGnSWD),
                .WRDATA      (ADIv5_WRDATA),
                .WREN        (ADIv5_WREN),
                .WRFULL      (swd_adiv5_WRFULL),
                .RDDATA      (swd_adiv5_RDDATA),
                .RDEN        (ADIv5_RDEN),
                .RDEMPTY     (swd_adiv5_RDEMPTY),
                .PHY_WRDATA  (swd_WRDATA),
                .PHY_WREN    (swd_WREN),
                .PHY_WRFULL  (swd_WRFULL),
                .PHY_RDDATA  (swd_RDDATA),
                .PHY_RDEN    (swd_RDEN),
                .PHY_RDEMPTY (swd_RDEMPTY)
                );   

endmodule // debug_mux


