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
    parameter DW    = 0)
   (
    input wire           rst_i,
    input wire           wr_clk_i,
    output wire          wr_en_o,
    output wire [DW-1:0] wr_data_o,
    input wire           full_i,
    input wire           rd_clk_i,
    // Output fifo 1
    output wire          f1_rd_en_o,
    input wire [DW-1:0]  f1_rd_data_i,
    input wire           f1_empty_i,
    // Output fifo 2
    output wire          f2_rd_en_o,
    input wire [DW-1:0]  f2_rd_data_i,
    input wire           f2_empty_i
    );

   // Host fifo definitions
   import host_fifo_pkg::*;

   function [DW-1:0] randvec;
      integer            idx;
      
      for (idx = DW ; idx>0 ; idx=idx-32)
	    randvec = (randvec << 32) | $urandom;
   endfunction

   reg [DW-1:0] mem [0:DEPTH-1];

   integer 	seed = 32'hdeadbeef;

   fifo_writer
     #(.WIDTH (DW))
   writer
     (.clk (wr_clk_i),
      .dout (wr_data_o),
      .wren (wr_en_o),
      .full (full_i));

   fifo_reader1
     #(.WIDTH (DW))
   reader1
     (.clk (rd_clk_i),
      .din  (f1_rd_data_i),
      .rden (f1_rd_en_o),
      .empty (f1_empty_i));

   fifo_reader1
     #(.WIDTH (DW))
   reader2
     (.clk (rd_clk_i),
      .din  (f2_rd_data_i),
      .rden (f2_rd_en_o),
      .empty (f2_empty_i));


   task fifo_write;
      input integer transactions_i;
      input real    write_rate;

      integer 	    index;
      integer 	    tmp;
      reg [DW-1:0]  data;
      integer 	    dw_idx;

      //$urandom (seed);
      
      begin
	     //Cap rate to [0.0-1.0]
	     if(write_rate > 1.0) write_rate = 1.0;
	     if(write_rate < 0.0) write_rate = 0.0;
	     writer.rate = write_rate;

	     index = 0;

	     @(posedge wr_clk_i);
	     while(index < transactions_i) begin
         
	        data = randvec();

	        mem[index % DEPTH] = data;
	        writer.write_word(data);

	        index = index + 1;
	     end
      end
   endtask

   task fifo_verify;
      input integer  transactions_i;
      input real     read_rate;
      output integer errors;
      input [DW-1:0] selmask;      
      input integer  cntshift;
      input integer  cntmask;
      
      
      integer        index;
      integer        cidx;
      
      reg [DW-1:0]   received;
      reg [DW-1:0]   expected;
      reg [DW-1:0]   cmd;
      reg [host_fifo_pkg::FIFO_PAYLOAD_WIDTH-1:0] cnt;
      
      begin
	     errors = 0;
         
	     index = 0;
	     @(posedge rd_clk_i);
	     while (index < transactions_i)
           begin

              // Get expected
	          cmd = mem[index % DEPTH];
              cnt = host_fifo_pkg::fifo_payload ((cmd >> cntshift) & cntmask);

              // Clear idx
              cidx = 0;
              
              // Verify command
              if ((cmd & selmask) != 0)
	            reader1.read_word(received);
              else
                reader2.read_word(received);
	          if(cmd !== received) 
                begin
	               $display("Error at index %0d. Expected 0x%4x, got 0x%4x", index, expected, received);
	               errors = errors + 1;
	            end
	          index = index + 1;                 
              
              // Verify data
              while (cidx < cnt)
                begin

                   // Get expected
                   expected = mem[index % DEPTH];
                   
                   // Read word
                   if ((cmd & selmask) != 0)
	                 reader1.read_word(received);
                   else
                     reader2.read_word(received);
                   
                   // Verify expected
	               if(expected !== received) 
                     begin
	                    $display("Error at index %0d. Expected 0x%4x, got 0x%4x", index, expected, received);
	                    errors = errors + 1;
	                 end
	               index = index + 1;
                   cidx = cidx + 1;
                   
                end // while (cidx < cnt)              
           end // while (index < transactions_i)
      end
      
      endtask
   
endmodule
