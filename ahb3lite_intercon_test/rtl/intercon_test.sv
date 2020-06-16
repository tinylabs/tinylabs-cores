module intercon_test
#(
  parameter build_synth = 0
 ) (
                      input CLK,
                      input RESET,
                      output PASS,
                      output FAIL
                      );

`include "ahb3lite_intercon.vh"

   // peripheral parameters - MUST match generator specs in intercon_test.core
   localparam MEM0_SZ = (1024);
   localparam MEM1_SZ = (1024);
   
   logic                     pass0, pass1;
   logic                     fail0, fail1;

   // Make sure both memory tests pass
   assign PASS = pass0 & pass1;
   assign FAIL = fail0 | fail1;

   logic                     RESETn;
   generate
      if (build_synth) begin : gen_reset_hold
         
         // RESET hold circuit
         logic [7:0]               RESET_CTR;
         
         always @(posedge CLK)
           begin
              if (RESET)
                RESET_CTR <= 'hff;
              else if (RESET_CTR > 0)
                RESET_CTR <= RESET_CTR - 1;
           end
         
         assign RESETn = (RESET_CTR != 0) ? 0 : 1;
      end // block: gen_reset_hold
      else begin : gen_reset_hold
         assign RESETn = RESET;
      end
   endgenerate
   
   // Master test vector
   ahb3lite_mvec
     #(
       .SLAVE_ADDR  (0),
       .SLAVE_SIZE  (MEM0_SZ),
       .SEED        ('hDEADBEEF)
       ) u_mvec0
       (
        .CLK    (CLK),
        .RESETn (RESETn),
        .HADDR  (ahb3_mvec0_HADDR),
        .HWDATA (ahb3_mvec0_HWDATA),
        .HWRITE (ahb3_mvec0_HWRITE),
        .HSIZE  (ahb3_mvec0_HSIZE),
        .HBURST (ahb3_mvec0_HBURST),
        .HPROT  (ahb3_mvec0_HPROT),
        .HTRANS (ahb3_mvec0_HTRANS),
        .HRDATA (ahb3_mvec0_HRDATA),
        .HRESP  (ahb3_mvec0_HRESP),
        .HREADY (ahb3_mvec0_HREADY),
        // Outputs
        .PASS (pass0),
        .FAIL (fail0)
      );
   assign ahb3_mvec0_HSEL = 1'b1;
   assign ahb3_mvec0_HMASTLOCK = 1'b0;

   // Master test vector
   ahb3lite_mvec
     #(
       .SLAVE_ADDR  ('h1000),
       .SLAVE_SIZE  (MEM1_SZ),
       .SEED        ('hCAFED00D)
       ) u_mvec1
       (
        .CLK    (CLK),
        .RESETn (RESETn),
        .HADDR  (ahb3_mvec1_HADDR),
        .HWDATA (ahb3_mvec1_HWDATA),
        .HWRITE (ahb3_mvec1_HWRITE),
        .HSIZE  (ahb3_mvec1_HSIZE),
        .HBURST (ahb3_mvec1_HBURST),
        .HPROT  (ahb3_mvec1_HPROT),
        .HTRANS (ahb3_mvec1_HTRANS),
        .HRDATA (ahb3_mvec1_HRDATA),
        .HRESP  (ahb3_mvec1_HRESP),
        .HREADY (ahb3_mvec1_HREADY),
        // Outputs
        .PASS (pass1),
        .FAIL (fail1)
      );
   assign ahb3_mvec1_HSEL = 1'b1;
   assign ahb3_mvec1_HMASTLOCK = 1'b0;
   
   
   // Delcare peripherals here
   ahb3lite_sram1rw
     #(
       .MEM_SIZE (MEM0_SZ),
       .HADDR_SIZE (32),
       .HDATA_SIZE (32),
       .TECHNOLOGY ("GENERIC"),
       .REGISTERED_OUTPUT ("NO")
       ) u_mem0 (
                 .HCLK      (CLK),
                 .HRESETn   (RESETn),
                 .HSEL      (ahb3_bram0_HSEL),
                 .HADDR     (ahb3_bram0_HADDR),
                 .HWDATA    (ahb3_bram0_HWDATA),
                 .HRDATA    (ahb3_bram0_HRDATA),
                 .HWRITE    (ahb3_bram0_HWRITE),
                 .HSIZE     (ahb3_bram0_HSIZE),
                 .HBURST    (ahb3_bram0_HBURST),
                 .HPROT     (ahb3_bram0_HPROT),
                 .HTRANS    (ahb3_bram0_HTRANS),
                 .HREADYOUT (ahb3_bram0_HREADYOUT),
                 .HREADY    (ahb3_bram0_HREADY),
                 .HRESP     (ahb3_bram0_HRESP)
                 );
   
   ahb3lite_sram1rw
     #(
       .MEM_SIZE (MEM1_SZ),
       .HADDR_SIZE (32),
       .HDATA_SIZE (32),
       .TECHNOLOGY ("GENERIC"),
       .REGISTERED_OUTPUT ("NO")
       ) u_mem1 (
                 .HCLK      (CLK),
                 .HRESETn   (RESETn),
                 .HSEL      (ahb3_bram1_HSEL),
                 .HADDR     (ahb3_bram1_HADDR),
                 .HWDATA    (ahb3_bram1_HWDATA),
                 .HRDATA    (ahb3_bram1_HRDATA),
                 .HWRITE    (ahb3_bram1_HWRITE),
                 .HSIZE     (ahb3_bram1_HSIZE),
                 .HBURST    (ahb3_bram1_HBURST),
                 .HPROT     (ahb3_bram1_HPROT),
                 .HTRANS    (ahb3_bram1_HTRANS),
                 .HREADYOUT (ahb3_bram1_HREADYOUT),
                 .HREADY    (ahb3_bram1_HREADY),
                 .HRESP     (ahb3_bram1_HRESP)
                 );

endmodule // intercon_test
