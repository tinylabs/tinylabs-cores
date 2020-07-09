/*
 *  FIFO testbench
 *
 *  Copyright (C) 2017  Olof Kindgren <olof.kindgren@gmail.com>
 *
 *  Permission to use, copy, modify, and/or distribute this software for any
 *  purpose with or without fee is hereby granted, provided that the above
 *  copyright notice and this permission notice appear in all copies.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 *  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 *  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 *  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 *  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 *  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 *  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */
module fifo_arb_tx_tb 
  #(parameter data_width  = 8,
    parameter depth_width = 8);

   localparam DEPTH = 1<<depth_width;
   localparam SELMASK = 1 << (data_width-1);
   localparam CNTMASK = 7 << (data_width-4);

   vlog_tb_utils vlog_tb_utils0();
   vlog_tap_generator #("fifo.tap", 1) vtg();

   reg clk = 1'b1;
   reg rst = 1'b1;

   always #11000 clk <= ~clk;
   initial #95000 rst <= 0;

   wire [data_width-1:0] wr_data;
   wire                  wr_en;
   wire [data_width-1:0] rd_data;
   wire                  rd_en;
   wire                  full;
   wire                  empty;
   
   wire                  c1_wren;
   wire                  c1_wrfull;
   wire [data_width-1:0] c1_wrdata;
   wire                  c2_wren;
   wire                  c2_wrfull;
   wire [data_width-1:0] c2_wrdata;
   
   
   fifo
     #(.DEPTH_WIDTH (depth_width),
       .DATA_WIDTH (data_width))
   fifo_out
     (
      .clk       (clk),
      .rst       (rst),

      .wr_en_i   (wr_en),
      .wr_data_i (wr_data),
      .full_o    (full),

      .rd_en_i   (rd_en),
      .rd_data_o (rd_data),
      .empty_o   (empty));

   /* Create arbiter */
   fifo_arb_tx
     #(.DWIDTH  (data_width),
       .AWIDTH  (depth_width),
       .SELMASK (SELMASK),
       .CNTMASK (CNTMASK))
   dut (
        // Global
        .CLK          (clk),
        .RESETn       (~rst),

        // Input 1
        .c1_wren      (c1_wren),
        .c1_wrfull    (c1_wrfull),
        .c1_wrdata    (c1_wrdata),

        // Input 2
        .c2_wren      (c2_wren),
        .c2_wrfull    (c2_wrfull),
        .c2_wrdata    (c2_wrdata),
        
        // Output
        .fifo_wren    (wr_en),
        .fifo_wrfull  (full),
        .fifo_wrdata  (wr_data)
        );
   
       
   fifo_tester
     #(.DEPTH   (DEPTH),
       .DW      (data_width),
       .SELMASK (SELMASK),
       .CNTSHIFT (4),
       .CNTMASK  (7))
   tester
     (.rst_i     (rst),
      .wr_clk_i  (clk),
      .rd_clk_i  (clk),

      // Read output FIFO
      .rd_en_o    (rd_en),
      .rd_data_o  (rd_data),
      .empty_i    (empty),

      // DUT inputs
      .f1_wr_en_o   (c1_wren),
      .f1_wr_data_o (c1_wrdata),
      .f1_full_i    (c1_wrfull),
      .f2_wr_en_o   (c2_wren),
      .f2_wr_data_o (c2_wrdata),
      .f2_full_i    (c2_wrfull));
   

   //integer               transactions = 30;
   integer               transactions = 247;

   integer 	 errors;

   initial begin
      if($value$plusargs("transactions=%d", transactions)) begin
	     $display("Setting number of transactions to %0d", transactions);
      end

      #95000 rst = 0;
      $display("Random input - verify fifos");
      //fork
	  tester.fifo_write(transactions , 1.0);
	  tester.fifo_verify(transactions, 1.0, errors);
      //join
      vtg.write_tc("Random input - verify fifos", !errors);
      $finish;
   end

endmodule // fifo_tb
