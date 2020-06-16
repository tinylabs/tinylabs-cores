// AHB3 master test vector

module ahb3lite_mvec #(
                       // LFSR params
                       parameter WIDTH = 32,
                       parameter SEED = 32'hdeadbeef,
                       parameter POLY = 32'h00200007,
                       // Slave size params
                       parameter SLAVE_ADDR = 0,
                       parameter SLAVE_SIZE = 1024
                       )
   (
    // Global signals
    input         CLK,
    input         RESETn,

    // AHB master interface
    output logic [31:0] HADDR,
    output logic [31:0] HWDATA,
    output logic        HWRITE,
    output logic [2:0]  HSIZE,
    output logic [2:0]  HBURST,
    output logic [3:0]  HPROT,
    output logic [1:0]  HTRANS,
    input [31:0]  HRDATA,
    input         HRESP,
    input         HREADY,

    output logic  PASS,
    output logic  FAIL
    );

   import ahb3lite_pkg::*;

   // LFSR state
   logic [WIDTH-1:0] lfsr; 

   // Slave state
   typedef enum {
                 STATE_WRITE,
                 STATE_VERIFY
                 } state_t;
   state_t           state;   
   logic [31:0]      addr;
   

   always @(posedge CLK)
     begin
        if (!RESETn)
          begin
             lfsr <= SEED;
             addr <= SLAVE_ADDR;
             state <= STATE_WRITE;
             PASS <= 0;
             FAIL <= 0;
             HTRANS <= HTRANS_IDLE;
          end
        else if (!FAIL)
          begin

             // Put transaction on bus
             if (HREADY && (addr < (SLAVE_ADDR + SLAVE_SIZE)))
               begin
                  HADDR <= addr;
                  HBURST <= 0;
                  HPROT <= 3;
                  HSIZE <= HSIZE_B32;
                  HTRANS <= HTRANS_NONSEQ;
                  HWRITE <= (state == STATE_WRITE) ? 1 : 0;
                  addr <= addr + 4;
               end // if (HREADY)

             // Read/write pipelined data
             if ((HTRANS != HTRANS_IDLE) & HREADY)
               begin

                  if (state == STATE_WRITE)
                    HWDATA <= lfsr;
                  else if ((HADDR > SLAVE_ADDR) && (HRDATA != lfsr))
                    FAIL <= 1;

                  // Increment LFSR
                  if (HREADY &&
                      (state != STATE_VERIFY) ||
                      (addr > (SLAVE_ADDR + 4)))
                    begin
                       lfsr[(WIDTH-2):0] <= lfsr[(WIDTH-1):1];
                       lfsr[WIDTH-1] <= ^(lfsr & POLY);
                    end

                  // Move to IDLE when complete
                  if (addr >= (SLAVE_ADDR + SLAVE_SIZE))
                    begin
                       HTRANS <= HTRANS_IDLE;
                       if (state == STATE_WRITE)
                         begin
                            state <= STATE_VERIFY;
                            addr <= SLAVE_ADDR;
                            lfsr <= SEED;
                         end
                    end
               end // if ((HTRANS != HTRANS_IDLE) & HREADY)

             // Success
             if ((addr == (SLAVE_ADDR + SLAVE_SIZE)) &&
                 (state == STATE_VERIFY) &&
                 (HTRANS == HTRANS_IDLE))
               PASS <= 1;

          end // else: !if(!RESETn)
     end // always @ (posedge CLK)
   
endmodule // ahb3lite_mvec
