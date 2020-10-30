/**
 *  Convert between HOST FIFO <=> JTAG DIRECT
 * 
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */

module host_jtag_convert
   (
    // System clock and reset
    input                        CLK,
    input                        RESETn,
    // ADIv5 FIFO interface
    input [7:0]                  HOST_WRDATA,
    input                        HOST_WREN,
    output logic                 HOST_WRFULL,
    output logic [7:0]           HOST_RDDATA,
    input                        HOST_RDEN,
    output logic                 HOST_RDEMPTY,
    // JTAG direct PHY FIFO interface
    input [JTAG_CMD_WIDTH-1:0]   JTAG_WRDATA,
    input                        JTAG_WREN,
    output                       JTAG_WRFULL,
    output [JTAG_RESP_WIDTH-1:0] JTAG_RDDATA,
    input                        JTAG_RDEN,
    output                       JTAG_RDEMPTY
    );


endmodule // host_jtag_convert



