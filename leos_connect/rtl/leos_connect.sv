/**
 *  Top-level definitions for leos_connect platform
 * 
 * Tiny Labs Inc
 * 2020
 */

module leos_connect
  #(
    parameter XILINX_ENC_CM3 = 0,
    parameter ROM_SZ         = 0,
    parameter RAM_SZ         = 0,
    parameter ROM_FILE       = "",
    parameter HOST_CLK_FREQ  = 0,
    parameter HOST_BAUD      = 0
  ) (
     // Clock and reset
     input              CLK,
     input              HOST_CLK,
     input              PORESETn,
     
     // JTAG/SWD
     input              TCK_SWDCLK,
     input              TDI,
     input              TMS_SWDIN,
     output             TDO,
     output             SWDOUT,
     output             SWDOUTEN,

     // UART transport
     input              UART_RX,
     output             UART_TX
   );

   // Implicit reset for autogen interconnect
   logic           RESETn;
   assign RESETn = PORESETn;   

   // Include generated AHB3lite interconnect crossbar
`include "ahb3lite_intercon.vh"
   
   // IRQs to cm3 core
   logic [15:0] irq;
      
   assign irq = {16'h0};

   // CPU reset controller
   logic        cpureset_n, sysresetreq;
   logic [3:0]  cpureset_ctr;
   always @(posedge CLK)
     begin
        if (!PORESETn | sysresetreq)
          cpureset_ctr <= 4'hf;
        else if (|cpureset_ctr)
          cpureset_ctr <= cpureset_ctr - 1;
     end
   assign cpureset_n = |cpureset_ctr ? 1'b0 : 1'b1;
   
   // Instantiate ROM
   ahb3lite_sram1rw
     #(
       .MEM_SIZE (ROM_SZ),
       .HADDR_SIZE (32),
       .HDATA_SIZE (32),
       .TECHNOLOGY ("GENERIC"),
       .REGISTERED_OUTPUT ("NO"),
       .LOAD_FILE (ROM_FILE)
       ) u_rom (
                .HCLK      (CLK),
                .HRESETn   (PORESETn),
                .HSEL      (ahb3_rom_HSEL),
                .HADDR     (ahb3_rom_HADDR),
                .HWDATA    (ahb3_rom_HWDATA),
                .HRDATA    (ahb3_rom_HRDATA),
                .HWRITE    (ahb3_rom_HWRITE),
                .HSIZE     (ahb3_rom_HSIZE),
                .HBURST    (ahb3_rom_HBURST),
                .HPROT     (ahb3_rom_HPROT),
                .HTRANS    (ahb3_rom_HTRANS),
                .HREADYOUT (ahb3_rom_HREADYOUT),
                .HREADY    (ahb3_rom_HREADY),
                .HRESP     (ahb3_rom_HRESP)
                );
   
   // Instantiate RAM
   ahb3lite_sram1rw
     #(
       .MEM_SIZE (RAM_SZ),
       .HADDR_SIZE (32),
       .HDATA_SIZE (32),
       .TECHNOLOGY ("GENERIC"),
       .REGISTERED_OUTPUT ("NO")
       ) u_ram (
                .HCLK      (CLK),
                .HRESETn   (PORESETn),
                .HSEL      (ahb3_ram_HSEL),
                .HADDR     (ahb3_ram_HADDR),
                .HWDATA    (ahb3_ram_HWDATA),
                .HRDATA    (ahb3_ram_HRDATA),
                .HWRITE    (ahb3_ram_HWRITE),
                .HSIZE     (ahb3_ram_HSIZE),
                .HBURST    (ahb3_ram_HBURST),
                .HPROT     (ahb3_ram_HPROT),
                .HTRANS    (ahb3_ram_HTRANS),
                .HREADYOUT (ahb3_ram_HREADYOUT),
                .HREADY    (ahb3_ram_HREADY),
                .HRESP     (ahb3_ram_HRESP)
                );

   
   // Transport fifo connections
   wire trnspt_fifo_wren, trnspt_fifo_wrfull;
   wire trnspt_fifo_rden, trnspt_fifo_rdempty;
   wire [7:0] trnspt_fifo_wrdata,
              trnspt_fifo_rddata;
   
   // Create host_bridge FIFOs
   wire hbrg_fifo_wren, hbrg_fifo_wrfull;
   wire hbrg_fifo_rden, hbrg_fifo_rdempty;
   wire [7:0] hbrg_fifo_wrdata,
              hbrg_fifo_rddata;
   dual_clock_fifo
     #(
       .ADDR_WIDTH   (4),
       .DATA_WIDTH   (8)
       ) u_fifo_ahb3_to_host (
                              // Clocks
                              .wr_clk_i  (CLK),
                              .rd_clk_i  (HOST_CLK),
                              // Shared reset
                              .wr_rst_i  (~PORESETn),
                              .rd_rst_i  (~PORESETn),
                              // Write interface (from AHB3 slave)
                              .wr_en_i   (hbrg_fifo_wren),
                              .wr_data_i (hbrg_fifo_wrdata),
                              .full_o    (hbrg_fifo_wrfull),
                              // Read interface (Host transport)
                              .rd_en_i   (trnspt_fifo_rden),
                              .rd_data_o (trnspt_fifo_rddata),
                              .empty_o   (trnspt_fifo_rdempty)
                              );
   dual_clock_fifo
     #(
       .ADDR_WIDTH   (4),
       .DATA_WIDTH   (8)
       ) u_fifo_host_to_ahb3 (
                              // Clocks
                              .wr_clk_i  (HOST_CLK),
                              .rd_clk_i  (CLK),
                              // Shared reset
                              .wr_rst_i  (~PORESETn),
                              .rd_rst_i  (~PORESETn),
                              // Write interface (Host transport)
                              .wr_en_i   (trnspt_fifo_wren),
                              .wr_data_i (trnspt_fifo_wrdata),
                              .full_o    (trnspt_fifo_wrfull),
                              // Read interface (AHB3 master)
                              .rd_en_i   (hbrg_fifo_rden),
                              .rd_data_o (hbrg_fifo_rddata),
                              .empty_o   (hbrg_fifo_rdempty)
                              );

   // Host bridge
   assign ahb3_host_mst_HSEL = 1;
   ahb3lite_host_bridge
     u_host_brg (
                 .CLK           (CLK    ),
                 .RESETn        (RESETn ),
                 // AHB3 master interface
                 .mst_HWRITE    (ahb3_host_mst_HWRITE  ),
                 .mst_HTRANS    (ahb3_host_mst_HTRANS  ),
                 .mst_HSIZE     (ahb3_host_mst_HSIZE   ),
                 .mst_HADDR     (ahb3_host_mst_HADDR   ),
                 .mst_HBURST    (ahb3_host_mst_HBURST  ),
                 .mst_HPROT     (ahb3_host_mst_HPROT   ),
                 .mst_HWDATA    (ahb3_host_mst_HWDATA  ),
                 .mst_HREADY    (ahb3_host_mst_HREADY  ),
                 .mst_HRDATA    (ahb3_host_mst_HRDATA  ),
                 .mst_HRESP     (ahb3_host_mst_HRESP   ),
                 // AHB3 slave interface
                 .slv_HREADY    (ahb3_host_slv_HREADY    ),
                 .slv_HWRITE    (ahb3_host_slv_HWRITE    ),
                 .slv_HSEL      (ahb3_host_slv_HSEL      ),
                 .slv_HTRANS    (ahb3_host_slv_HTRANS    ),
                 .slv_HSIZE     (ahb3_host_slv_HSIZE     ),
                 .slv_HADDR     (ahb3_host_slv_HADDR     ),
                 .slv_HBURST    (ahb3_host_slv_HBURST    ),
                 .slv_HPROT     (ahb3_host_slv_HPROT     ),
                 .slv_HWDATA    (ahb3_host_slv_HWDATA    ),
                 .slv_HREADYOUT (ahb3_host_slv_HREADYOUT ),
                 .slv_HRDATA    (ahb3_host_slv_HRDATA    ),
                 .slv_HRESP     (ahb3_host_slv_HRESP     ),
                 // FIFO interface
                 .fifo_rden     (hbrg_fifo_rden     ),
                 .fifo_rdempty  (hbrg_fifo_rdempty  ),
                 .fifo_rddata   (hbrg_fifo_rddata   ),
                 .fifo_wren     (hbrg_fifo_wren     ),
                 .fifo_wrfull   (hbrg_fifo_wrfull   ),
                 .fifo_wrdata   (hbrg_fifo_wrdata   )
                 );

   // Select transport layer
   uart_transport
     #(
       .FREQ  (HOST_CLK_FREQ),
       .BAUD  (HOST_BAUD)
       ) u_transport (
                      /* Core signals */
                      .CLK    (HOST_CLK),
                      .RESETn (RESETn),
                      /* FIFO interface */
                      .FIFO_WREN  (trnspt_fifo_wren),
                      .FIFO_RDEN  (trnspt_fifo_rden),
                      .FIFO_EMPTY (trnspt_fifo_rdempty),
                      .FIFO_FULL  (trnspt_fifo_wrfull),
                      .FIFO_DIN   (trnspt_fifo_rddata),
                      .FIFO_DOUT  (trnspt_fifo_wrdata),
                      /* UART outputs */
                      .TX_PIN     (UART_TX),
                      .RX_PIN     (UART_RX)
                      );
   
   // Enable master ports
   assign ahb3_cm3_code_HSEL = 1'b1;
   assign ahb3_cm3_sys_HSEL = 1'b1;
   
   // Instantiate cortex-m3 core
   cm3_core
     #(
       .XILINX_ENC_CM3  (XILINX_ENC_CM3),
       .NUM_IRQ         (16)
       )
     u_cm3 (
            // Clock and reset
            .FCLK         (CLK),
            .HCLK         (CLK),
            .PORESETn     (PORESETn),
            .CPURESETn    (cpureset_n),
            .SYSRESETREQ  (sysresetreq),
            
            // IRQs
            .INTISR       (irq),
            .INTNMI       (1'b0),
            
            // Debug
            .SWCLKTCK     (TCK_SWDCLK),
            .SWDITMS      (TMS_SWDIN),
            .SWDO         (SWDOUT),
            .SWDOEN       (SWDOUTEN),
            .nTRST        (1'b1),
            .TDI          (TDI),
            .TDO          (TDO),
            .nTDOEN       (),
            .SWV          (),
            
            // Status
            .HALTED       (),
            .LOCKUP       (),
            .JTAGNSW      (),
            
            // AHB3 code master
            .code_HADDR     (ahb3_cm3_code_HADDR),
            .code_HWDATA    (ahb3_cm3_code_HWDATA),
            .code_HTRANS    (ahb3_cm3_code_HTRANS),
            .code_HSIZE     (ahb3_cm3_code_HSIZE),
            .code_HBURST    (ahb3_cm3_code_HBURST),
            .code_HPROT     (ahb3_cm3_code_HPROT),
            .code_HWRITE    (ahb3_cm3_code_HWRITE),
            .code_HMASTLOCK (ahb3_cm3_code_HMASTLOCK),
            .code_HRDATA    (ahb3_cm3_code_HRDATA),
            .code_HRESP     (ahb3_cm3_code_HRESP),
            .code_HREADY    (ahb3_cm3_code_HREADY),

            // AHB3 system master
            .sys_HADDR     (ahb3_cm3_sys_HADDR),
            .sys_HWDATA    (ahb3_cm3_sys_HWDATA),
            .sys_HTRANS    (ahb3_cm3_sys_HTRANS),
            .sys_HSIZE     (ahb3_cm3_sys_HSIZE),
            .sys_HBURST    (ahb3_cm3_sys_HBURST),
            .sys_HPROT     (ahb3_cm3_sys_HPROT),
            .sys_HWRITE    (ahb3_cm3_sys_HWRITE),
            .sys_HMASTLOCK (ahb3_cm3_sys_HMASTLOCK),
            .sys_HRDATA    (ahb3_cm3_sys_HRDATA),
            .sys_HRESP     (ahb3_cm3_sys_HRESP),
            .sys_HREADY    (ahb3_cm3_sys_HREADY)
            );
     
endmodule // cm3_min_soc
