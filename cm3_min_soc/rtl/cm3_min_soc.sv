/**
 *  Minimum SoC using a cortex-m3 core and a couple BRAM for code/RAM
 * 
 * Tiny Labs Inc
 * 2020
 */

module cm3_min_soc
  #(
    parameter XILINX_ENC_CM3 = 0,
    parameter ROM_SZ = (16384),
    parameter RAM_SZ = (16384)
  ) (
     // Clock and reset
     input        CLK,
     input        RESETn,
     input        CPURESETn,
     
     // JTAG/SWD
     input        TCK_SWDCLK,
     input        TDI,
     input        TMS_SWDIN,
     output       TDO,
     output       SWDOUT,
     output       SWDOUTEN,

     // 1-bit gpio output
     output logic LED
   );
   
   // Include generated AHB3lite interconnect crossbar
`include "ahb3lite_intercon.vh"

   // APB4 local bus
   // TODO: Create generator so more peripherals can be added via mux generation
   localparam  APB4_PDATA_SIZE = 8;
   localparam  APB4_PADDR_SIZE = 8;
   logic                           apb4_PSEL, apb4_PENABLE, apb4_PWRITE, apb4_PREADY, apb4_PSLVERR;
   logic [2:0]                     apb4_PPROT;
   logic [(APB4_PDATA_SIZE/8)-1:0] apb4_PSTRB;
   logic [APB4_PADDR_SIZE-1:0]     apb4_PADDR;
   logic [APB4_PADDR_SIZE-1:0]     apb4_PWDATA;
   logic [APB4_PADDR_SIZE-1:0]     apb4_PRDATA;
   
   // GPIO port
   logic [APB4_PDATA_SIZE-1:0]     gpio_i, gpio_o, gpio_oe;
   logic                           irq_o;
   
   // IRQs to cm3 core
   logic [15:0] irq;
   
   // Disable IRQs on minimal implementation
   assign irq = 16'h0;

   // Just use output for LED
   assign LED = gpio_oe[0] ? gpio_o[0] : 1'b0;
   
   // Instantiate ROM
   ahb3lite_sram1rw
     #(
       .MEM_SIZE (ROM_SZ),
       .HADDR_SIZE (32),
       .HDATA_SIZE (32),
       .TECHNOLOGY ("GENERIC"),
       .REGISTERED_OUTPUT ("NO")
       ) u_rom (
                .HCLK      (CLK),
                .HRESETn   (RESETn),
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
                .HRESETn   (RESETn),
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

   // Instantiate AHB3 <=> APB4 bridge
   ahb3lite_apb_bridge
     #(
       .HADDR_SIZE    (32),
       .HDATA_SIZE    (32),
       .PADDR_SIZE    (APB4_PADDR_SIZE),
       .PDATA_SIZE    (APB4_PDATA_SIZE)
       ) u_ahb_apb_brg (
                        // AHB3 slave interface
                        .HCLK      (CLK),
                        .HRESETn   (RESETn),
                        .HSEL      (ahb3_apb_brg_HSEL),
                        .HADDR     (ahb3_apb_brg_HADDR),
                        .HWDATA    (ahb3_apb_brg_HWDATA),
                        .HRDATA    (ahb3_apb_brg_HRDATA),
                        .HWRITE    (ahb3_apb_brg_HWRITE),
                        .HSIZE     (ahb3_apb_brg_HSIZE),
                        .HBURST    (ahb3_apb_brg_HBURST),
                        .HPROT     (ahb3_apb_brg_HPROT),
                        .HTRANS    (ahb3_apb_brg_HTRANS),
                        .HREADYOUT (ahb3_apb_brg_HREADYOUT),
                        .HREADY    (ahb3_apb_brg_HREADY),
                        .HRESP     (ahb3_apb_brg_HRESP),
                        .HMASTLOCK (1'b0),
                        // APB4 master interface
                        .PCLK      (CLK),
                        .PRESETn   (RESETn),
                        .PSEL      (apb4_PSEL),
                        .PENABLE   (apb4_PENABLE),
                        .PPROT     (apb4_PPROT),
                        .PWRITE    (apb4_PWRITE),
                        .PSTRB     (apb4_PSTRB),
                        .PADDR     (apb4_PADDR),
                        .PWDATA    (apb4_PWDATA),
                        .PRDATA    (apb4_PRDATA),
                        .PREADY    (apb4_PREADY),
                        .PSLVERR   (apb4_PSLVERR)
                        );

   // Instantiate GPIO peripheral
   apb_gpio
     #(
       .PDATA_SIZE   (8)
       ) u_gpio (
                 // APB4 interface
                 .PCLK      (CLK),
                 .PRESETn   (RESETn),
                 .PSEL      (apb4_PSEL),
                 .PENABLE   (apb4_PENABLE),
                 .PWRITE    (apb4_PWRITE),
                 .PSTRB     (apb4_PSTRB),
                 .PADDR     (apb4_PADDR[3:0]),
                 .PWDATA    (apb4_PWDATA),
                 .PRDATA    (apb4_PRDATA),
                 .PREADY    (apb4_PREADY),
                 .PSLVERR   (apb4_PSLVERR),
                 // GPIO/IRQ out
                 .irq_o     (irq_o),
                 .gpio_i    (gpio_i),
                 .gpio_o    (gpio_o),
                 .gpio_oe   (gpio_oe)
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
            .PORESETn     (RESETn),
            .CPURESETn    (CPURESETn),
            .SYSRESETREQ  (),
            
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
