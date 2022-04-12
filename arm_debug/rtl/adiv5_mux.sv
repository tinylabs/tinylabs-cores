/**
 *  MUX two ADIv5 cores and provide direct access to jtag_phy
 * 
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */
import adiv5_pkg::*;

module adiv5_mux #( parameter FIFO_AW = 2 )
   (
    // System clock and reset
    input                               CLK,
    input                               SYS_RESETn,
    // PHY clock
    input                               PHY_CLK,
    input                               PHY_CLKn,
    input                               PHY_RESETn,
    // Select interface
    input                               JTAGnSWD,
    // ADIv5 FIFO interface
    input [ADIv5_CMD_WIDTH-1:0]         ADIv5_WRDATA,
    input                               ADIv5_WREN,
    output logic                        ADIv5_WRFULL,
    output logic [ADIv5_RESP_WIDTH-1:0] ADIv5_RDDATA,
    input                               ADIv5_RDEN,
    output logic                        ADIv5_RDEMPTY,
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

   // Internal phy signals
   logic                                jtag_TCK, jtag_TMS, jtag_TDI;
   logic                                swd_TCK, swd_TMSOUT, swd_TMSOE;

   // MUX hardware signals
   assign TCK    = JTAGnSWD ? jtag_TCK : swd_TCK;
   assign TDI    = JTAGnSWD ? jtag_TDI : 1'b0;
   assign TMSOUT = JTAGnSWD ? jtag_TMS : swd_TMSOUT;
   assign TMSOE  = JTAGnSWD ? 1'b1 : swd_TMSOE;

   // MUX ADIv5 interface
   assign ADIv5_WRFULL = JTAGnSWD ? jtag_adiv5_WRFULL : swd_adiv5_WRFULL;
   assign ADIv5_RDDATA = JTAGnSWD ? jtag_adiv5_RDDATA : swd_adiv5_RDDATA;
   assign ADIv5_RDEMPTY = JTAGnSWD ? jtag_adiv5_RDEMPTY : swd_adiv5_RDEMPTY;
   
   // Instantiate JTAG phy
   jtag_phy #(.FIFO_AW (FIFO_AW + 1))
   u_jtag_phy (
               .CLK        (CLK),
               .SYS_RESETn (SYS_RESETn & JTAGnSWD),
               .PHY_CLK    (PHY_CLK),
               .PHY_CLKn   (PHY_CLKn),
               .PHY_RESETn (PHY_RESETn & JTAGnSWD),
               .WRDATA     (jtag_WRDATA),
               .WREN       (jtag_WREN),
               .WRFULL     (jtag_WRFULL),
               .RDDATA     (jtag_RDDATA),
               .RDEN       (jtag_RDEN),
               .RDEMPTY    (jtag_RDEMPTY),
               .TCK        (jtag_TCK),
               .TMS        (jtag_TMS),
               .TDI        (jtag_TDI),
               .TDO        (TDO)
               );
   
   // Instantiate SWD phy
   swd_phy #(.FIFO_AW (FIFO_AW + 1))
   u_swd_phy (
              .CLK        (CLK),
              .SYS_RESETn (SYS_RESETn & ~JTAGnSWD),
              .PHY_CLK    (PHY_CLK),
              .PHY_CLKn   (PHY_CLKn),
              .PHY_RESETn (PHY_RESETn & ~JTAGnSWD),
              .WRDATA     (swd_WRDATA),
              .WREN       (swd_WREN),
              .WRFULL     (swd_WRFULL),
              .RDDATA     (swd_RDDATA),
              .RDEN       (swd_RDEN),
              .RDEMPTY    (swd_RDEMPTY),
              .SWDCLK     (swd_TCK),
              .SWDIN      (TMSIN),
              .SWDOUT     (swd_TMSOUT),
              .SWDOE      (swd_TMSOE)
              );

   // Instantiate JTAG ADIv5
   jtag_adiv5 #(.FIFO_AW (FIFO_AW))
   u_jtag_adiv5 (
                 .CLK         (CLK),
                 .RESETn      (SYS_RESETn & JTAGnSWD),
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
                .RESETn      (SYS_RESETn & ~JTAGnSWD),
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


