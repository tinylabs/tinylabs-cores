/**
 * SWD (Serial Wire Debug) PHY layer - Fully pipelined with async PHY_CLK
 *  domain to operate at arbitrary speeds.
 *
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */

module swd_phy
  # (parameter OWIDTH = 64,
     parameter IWIDTH = 38,
     parameter _OWIDTH = OWIDTH + (3 * $clog2(OWIDTH)),
     parameter _IWIDTH = IWIDTH + $clog2(IWIDTH) - 1
     )
   (
    input                CLK,
    input                PHY_CLK,
    input                RESETn,
    input                ENABLE,
    
    // FIFO interface IN
    input [_OWIDTH-1:0]  WRDATA,
    input                WREN,
    output               WRFULL,

    // FIFO interface OUT
    output [_IWIDTH-1:0] RDDATA, 
    input                RDEN,
    output               RDEMPTY,

    // Hardware interface
    output logic         SWDCLK,
    input                SWDIN,
    output logic         SWDOUT,
    output logic         SWDOE
   );


   // Internal variables
   logic                 busy, valid;
   logic                 rden, wren, empty, full;

   // Output variable
   logic [$clog2(OWIDTH)-1:0] ctr;
   logic [$clog2(OWIDTH)-1:0] olen, t0, t1;
   logic [$clog2(OWIDTH)-1:0] lenp, t0p, t1p;                     
   logic [OWIDTH-1:0]         so, sop;
   
   // Input variables
   logic [IWIDTH-1:0]         si;
   logic [$clog2(IWIDTH)-1:0] ilen;
   
   // Input FIFO
   // LEN, T0, T1, SO
   dual_clock_fifo #(
                     .ADDR_WIDTH   (2),
                     .DATA_WIDTH   (_OWIDTH))
   u_phy_in (
             // Interface domain
             .wr_clk_i   (CLK),
             .wr_rst_i   (~RESETn),
             .wr_data_i  (WRDATA),
             .wr_en_i    (WREN),
             .full_o     (WRFULL),
             // PHY domain
             .rd_clk_i   (PHY_CLK),
             .rd_rst_i   (~RESETn),
             .rd_data_o  ({lenp, t0p, t1p, sop}),
             .rd_en_i    (rden),
             .empty_o    (empty)
             );
   
   // Output FIFO
   // LEN, SI
   dual_clock_fifo #(
                     .ADDR_WIDTH   (2),
                     .DATA_WIDTH   (_IWIDTH))
   u_phy_out (
             // PHY domain
             .wr_clk_i   (PHY_CLK),
             .wr_rst_i   (~RESETn),
              // One spurious bit at the beginning and end
             .wr_data_i  ({si[IWIDTH-2:0], ilen - 6'h1}),
             .wr_en_i    (wren & !full),
             .full_o     (full),
             // Interface domain
             .rd_clk_i   (CLK),
             .rd_rst_i   (~RESETn),
             .rd_data_o  (RDDATA),
             .rd_en_i    (RDEN),
             .empty_o    (RDEMPTY)
             );

   // Read if data and not busy
   assign rden = !empty & !busy;

   // SWD clocks on both edges
   always @(posedge PHY_CLK, negedge PHY_CLK)
     begin

        if (!RESETn | !ENABLE)
          begin
             SWDOE <= 1;
             SWDOUT <= 0;
             busy <= 0;
             valid <= 0;
             ctr <= 6'(OWIDTH - 1);
             ilen <= 0;
          end

        // RESETn deasserted
        else
          begin
             
             // Positive edge
             if (PHY_CLK)
               begin

                  // Release busy early for pipelined access
                  if (ctr == (olen - 3))
                    busy <= 0;
                  // Data valid cycle after read
                  else if (rden)
                    begin
                       valid <= 1;
                       busy <= 1;
                    end
                  else
                    valid <= 0;

                  // Write to FIFO if data is available
                  if ((ilen != 0) && (ctr == (olen - 2)))
                    wren <= 1;
                  else
                    wren <= 0;

                  // Latch into working variables when valid
                  if (valid)
                    begin
                       olen <= lenp;
                       t0 <= t0p - 1;
                       t1 <= t1p - 1;
                       ctr <= 0;
                       ilen <= 0;
                       si <= 0;

                       // Clock out first bit
                       SWDOUT <= sop[0];
                       so <= {1'b0, sop[OWIDTH-1:1]};
                       SWDCLK <= 1;
                    end

                  // Push to FIFO when done
                  else if (ctr == olen)
                    begin
                       // Transaction done
                       ctr <= 6'(OWIDTH - 1);
                    end

                  // Clock out while transation is valid
                  else if (ctr < olen)
                    begin
                       
                       // Check error
                       if ((t0 == 7) && (ctr == 12))
                         begin

                            // Drive if this was read
                            // Is this still needed?
                            if ((si[2:0] != 3'b100) && (t1 > 12))
                              begin
                                 SWDOE <= 1;
                                 t1 <= 0;
                                 so <= {64{1'b0}};
                              end
                         end

                       // Write when SWDOE enabled
                       if (SWDOE)
                         begin
                            SWDOUT <= so[0];
                            so <= {1'b0, so[OWIDTH-1:1]};
                         end
                       // Read from slave
                       else if (!SWDOE)
                         begin
                            si <= {si[IWIDTH-2:0], SWDIN};
                            ilen <= ilen + 1;
                         end
                       
                       // Switch directions when counter matches
                       if ((ctr == t0) || (ctr == t1))
                         SWDOE <= ~SWDOE;                       

                       // Increment counter
                       ctr <= ctr + 1;

                       // Clock while transaction valid
                       if (ctr < (olen - 1))
                         SWDCLK <= 1;

                    end // if (ctr < olen)
               end // if (PHY_CLK)
             
             // Negative edge
             else
               begin

                  // Drive clock when in transaction
                  if (ctr < olen)
                    begin
                       SWDCLK <= 0;                                   
                    end
                  
               end // else: !if(PHY_CLK)
             
          end // else: !if(!RESETn | !ENABLE)
        
     end // always @ (posedge PHY_CLK, negedge PHY_CLK)
   
   
endmodule // swd_phy

