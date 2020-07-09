/*
 *  FIFO stimuli generator/checker
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
module fifo_tester
  #(parameter DEPTH = 0,
    parameter DW    = 0,
    parameter SELMASK = 0,
    parameter CNTSHIFT = 0,
    parameter CNTMASK = 0)
   (
    input wire           rst_i,
    input wire           wr_clk_i,
    input wire           rd_clk_i,
    // DUT output
    input wire [DW-1:0]  rd_data_o,
    input wire           empty_i,
    output wire          rd_en_o,
    // DUT inputs
    output wire          f1_wr_en_o,
    output wire [DW-1:0] f1_wr_data_o,
    input wire           f1_full_i,
    output wire          f2_wr_en_o,
    output wire [DW-1:0] f2_wr_data_o,
    input wire           f2_full_i
    );

   function [DW-1:0] randvec;
      integer            idx;
      
      for (idx = DW ; idx>0 ; idx=idx-32)
	    randvec = (randvec << 32) | $urandom;
   endfunction

   reg [DW-1:0] mem [0:DEPTH-1];

   integer 	seed = 32'hdeadbeef;

   fifo_writer
     #(.WIDTH (DW))
   writer1
     (.clk (wr_clk_i),
      .dout (f1_wr_data_o),
      .wren (f1_wr_en_o),
      .full (f1_full_i));

   fifo_writer
     #(.WIDTH (DW))
   writer2
     (.clk (wr_clk_i),
      .dout (f2_wr_data_o),
      .wren (f2_wr_en_o),
      .full (f2_full_i));

   fifo_reader1
     #(.WIDTH (DW))
   reader
     (.clk (rd_clk_i),
      .din  (rd_data_o),
      .rden (rd_en_o),
      .empty (empty_i));


   task fifo_write;
      input integer transactions_i;
      input real    write_rate;

      integer 	    index;
      integer 	    tmp;
      reg [DW-1:0]  data;
      reg [DW-1:0]  cmd;
      integer 	    dw_idx;
      integer       cnt;
      
      $urandom (seed);
      
      begin
	     writer1.rate = 1.0;
	     writer2.rate = 1.0;
	     index = 0;

	     @(posedge wr_clk_i);
	     while(index < transactions_i) begin
         
	        cmd = randvec();
	        mem[index % DEPTH] = cmd;
            tmp = (data >> CNTSHIFT) & CNTMASK;
            case (tmp)
              0: cnt = 0;
              1: cnt = 1;
              2: cnt = 2;
              3: cnt = 4;
              4: cnt = 8;
              default : cnt = 0;
            endcase // case (cnt)

            // Select fifo for command
            if (cmd & SELMASK)
              writer1.write_word (cmd);
            else
              writer2.write_word (cmd);
            index++;
            
            // Loop over count index
            for (int i = 0; i < cnt; i++)
              begin

                 // Generate another random word
	             data = randvec();
	             mem[index % DEPTH] = data;
                 if (cmd & SELMASK)
                   writer1.write_word (data);
                 else
                   writer2.write_word (data);
	             index = index + 1;
              end
	     end
      end
   endtask

   task fifo_verify;
      input integer  transactions_i;
      input real     read_rate;
      output integer errors;
      
      
      integer        index;
      integer        cidx;
      
      reg [DW-1:0]   received;
      reg [DW-1:0]   expected;
      reg [DW-1:0]   cmd;
      reg [3:0]      cnt;
      
      begin
	     errors = 0;
         
	     index = 0;
	     @(posedge rd_clk_i);
	     while (index < transactions_i)
           begin
              
	          reader.read_word(received);
              index++;
           end // while (index < transactions_i)
      end
      
      endtask
   
endmodule
