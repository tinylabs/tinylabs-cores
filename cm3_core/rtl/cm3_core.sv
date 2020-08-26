/**
 *  ARM Cortex-M3 wrapper
 * 
 *  Tiny Labs Inc
 *  2020
 *
 * Parameters:
 *   NUM_IRQ - Number of IRQs to core (fixed if XILINX_ENC_CM3 not defined)
 * 
 * Defines:
 *   XILINX_ENC_CM3 - Define to synthesize full core for xilinx (using encrypted IP)
 *                  This should be faster and allow full IRQ use
 *                  Default is fixed obsfucated core (fixed @ 16 IRQs)
 **/

module cm3_core #(
                  parameter NUM_IRQ = 16,
                  parameter XILINX_ENC_CM3 = 0,
                  parameter SINGLE_MEMORY = 0,
                  parameter CACHE_ENABLE = 0,
                  parameter ROM_SZ = 0,
                  parameter RAM_SZ = 0
                  )
   (
    // Clock and reset
    input               FCLK, // Free running clock
    input               HCLK, // System clock
    input               PORESETn, // Reset everything (including debug)
    input               CPURESETn, // Reset processor
    output              SYSRESETREQ, // System reset request
    
    // IRQs
    input [NUM_IRQ-1:0] INTISR, // IRQs
    input               INTNMI, // Non-maskable IRQ

    // JTAG/SWD
    input               SWCLKTCK, // JTAG CLK/SWDCLK
    input               SWDITMS, // JTAG TMS/SWDIN
    output logic        SWDO, // SWDOUT
    output logic        SWDOEN, // SWDIO output enable
    input               nTRST, // JTAG reset
    input               TDI, // JTAG TDI
    output logic        TDO, // JTAG TDO
    output logic        nTDOEN, // TDO output enable
    output logic        SWV, // Optional serial wire viewer
    
    // Core status
    output logic        HALTED, // Core halted by debug
    output logic        LOCKUP, // Core is locked up
    output logic        JTAGNSW, // Active debug interface (JTAG=1/SWD=0)
    
    // AHB3lite code bus (muxed icode/dcode)
    output logic [31:0] code_HADDR,
    output logic [31:0] code_HWDATA,
    output logic [ 1:0] code_HTRANS,
    output logic [ 2:0] code_HSIZE,
    output logic [ 2:0] code_HBURST,
    output logic [ 3:0] code_HPROT,
    output logic        code_HWRITE,
    output logic        code_HMASTLOCK,
    input [31:0]        code_HRDATA,
    input               code_HRESP,
    input               code_HREADY,

    // AHB3lite system bus (access >= 0x2000.0000)
    output logic [31:0] sys_HADDR,
    output logic [31:0] sys_HWDATA,
    output logic [ 1:0] sys_HTRANS,
    output logic [ 2:0] sys_HSIZE,
    output logic [ 2:0] sys_HBURST,
    output logic [ 3:0] sys_HPROT,
    output logic        sys_HWRITE,
    output logic        sys_HMASTLOCK,
    input [31:0]        sys_HRDATA,
    input               sys_HRESP,
    input               sys_HREADY
    );
   
   // ICODE AHB-lite bus interconnect
   wire                 hreadyi;
   wire [31:0]          hrdatai;
   wire [1:0]           hrespi;
   wire [1:0]           htransi;
   wire [2:0]           hsizei;
   wire [31:0]          haddri;
   wire [2:0]           hbursti;
   wire [3:0]           hproti;
   wire [1:0]           memattri;
   
   // DCODE AHB-lite bus
   wire                 hreadyd;
   wire [31:0]          hrdatad;
   wire [1:0]           hrespd;
   wire                 exrespd;
   wire [1:0]           hmasterd;
   wire [1:0]           htransd;
   wire [2:0]           hsized;
   wire [31:0]          haddrd;
   wire [2:0]           hburstd;
   wire [3:0]           hprotd;
   wire [1:0]           memattrd;
   wire                 hwrited;
   wire [31:0]          hwdatad;
   wire                 exreqd;

   // HMASTER unused
   wire [1:0]           hmasters;

   // memattrs unused
   wire [1:0]           memattrs;
   
   // Sys bus exclusive signals
   wire                 exreqs;
   wire                 exresps;
   wire                 hwrites; // Intermediate HWRITE signal

   // System address mux
   wire [31:0]          sys_haddr;
   
   // Loopback power request
   wire                 cdbgpwrup;

   // For constraints
   (* dont_touch = "yes" *) wire cm3_sys;
   (* dont_touch = "yes" *) wire cm3_dbg;
   assign cm3_sys = HCLK;
   assign cm3_dbg = SWCLKTCK;
   
   // Create exclusive access monitor for sys bus
   cm3_excl_mon
     u_sys_mon (
                .CLK       (HCLK),
                .RESETn    (PORESETn),
                .HALTED    (HALTED),
                .HADDR     (sys_HADDR),
                .HWRITE    (hwrites),
                .HWRITEOUT (sys_HWRITE),
                .EXREQ     (exreqs),
                .EXRESP    (exresps)
                );
   
   // Create icode/dcode mux
   cm3_code_mux
     u_code_mux (
                 // Global signals
                 .HCLK    (HCLK),
                 .HRESETn (PORESETn),
                 
                 // INPUT: icode bus
                 .HADDRI  (haddri),
                 .HTRANSI (htransi),
                 .HSIZEI  (hsizei),
                 .HBURSTI (hbursti),
                 .HPROTI  (hproti),
                 .HRDATAI (hrdatai),
                 .HREADYI (hreadyi),
                 .HRESPI  (hrespi),
                 
                 // INPUT: dcode bus
                 .HADDRD  (haddrd),
                 .HTRANSD (htransd),
                 .HSIZED  (hsized),
                 .HBURSTD (hburstd),
                 .HPROTD  (hprotd),
                 .HWDATAD (hwdatad),
                 .HWRITED (hwrited),
                 .HRDATAD (hrdatad),
                 .HREADYD (hreadyd),
                 .HRESPD  (hrespd),
                 .EXREQD  (exreqd),
                 .EXRESPD (exrespd),
                 
                 // OUTPUT: code bus
                 .HADDRC  (code_HADDR),
                 .HWDATAC (code_HWDATA),
                 .HTRANSC (code_HTRANS),
                 .HWRITEC (code_HWRITE),
                 .HSIZEC  (code_HSIZE),
                 .HBURSTC (code_HBURST),
                 .HPROTC  (code_HPROT),
                 .HRDATAC (code_HRDATA),
                 .HREADYC (code_HREADY),
                 .HRESPC  ({1'b0, code_HRESP}),
                 .EXREQC  (),
                 .EXRESPC (1'b1) // Disable exclusive access on code bus
                 );

   // Generate DATA accesses directly after ROM when enabled.
   generate
      if (SINGLE_MEMORY == 1) begin : mux_mem
         assign sys_HADDR = (sys_haddr >= 32'h2000_0000) & (sys_haddr < (32'h2000_0000 + RAM_SZ)) ?
                            (sys_haddr - 32'h2000_0000) + ROM_SZ :
                            sys_haddr;
      end
      else begin : mux_mem
         assign sys_HADDR = sys_haddr; // Pass thru
      end
   endgenerate

   generate
      if (CACHE_ENABLE == 1) begin : gen_cache

         // Add cache logic here
         
      end
   endgenerate
   
   // Instantiate core wrapper
   generate
      if (XILINX_ENC_CM3) begin : gen_cm3
         
         // Instantiate encrypted xilinx core
         CORTEXM3INTEGRATION
           #(
             .NUM_IRQ   (NUM_IRQ)
             )
         u_cm3 (
                // Clocks
                .FCLK        (FCLK),
                .HCLK        (HCLK),
                .TRACECLKIN  (HCLK),
                .STCLK       (1'b1), // Not actual clock
                
                // Reset
                .PORESETn    (PORESETn),
                .SYSRESETn   (CPURESETn),
                .SYSRESETREQ (SYSRESETREQ),
                
                // Interrupts
                .INTISR      (INTISR),
                .INTNMI      (INTNMI),
                .AUXFAULT    (32'h0),
                
                // Debug
                .SWCLKTCK    (SWCLKTCK),
                .nTRST       (nTRST),
                .SWDITMS     (SWDITMS),
                .TDI         (TDI),
                .TDO         (TDO),
                .nTDOEN      (nTDOEN),
                .SWV         (SWV),
                .SWDO        (SWDO),
                .SWDOEN      (SWDOEN),
                .JTAGNSW     (JTAGNSW),
                
                // Power management
                .CDBGPWRUPREQ (cdbgpwrup),
                .CDBGPWRUPACK (cdbgpwrup),
                .EDBGRQ       (1'b0),      // What is this?
                .DBGRESTART   (1'b0),      // Multiproc debug support?
                .DBGRESTARTED (),
                .ISOLATEn     (1'b1),      // Isolate core power domain
                .RETAINn      (1'b1),      // Retain state in power down
                
                // Wakeup controller
                .WICENREQ     (1'b0),      // Wakeup req from PMIC?
                .WICENACK     (),
                .WAKEUP       (),
                
                // Clock gating/bypass
                .CGBYPASS     (1'b0),
                .RSTBYPASS    (1'b0),
                .GATEHCLK     (),
                
                // Miscellaneous
                .SE            (1'b0),     // Scan enable?
                .BIGEND        (1'b0),     // Always little endian
                .STCALIB       (26'h0),    // Systick calib
                .FIXMASTERTYPE (1'b1),     // Needs to be 1
                .TSVALUEB      (48'h0),    // TPIU timestamp
                .TSCLKCHANGE   (1'b0),     // Not used
                .MPUDISABLE    (1'b0),
                .DBGEN         (1'b1),
                .TXEV          (),         // TX event output
                .RXEV          (1'b0),     // RX event input
                .INTERNALSTATE (),

                // Traceport - unused
                .TRACEDATA     (),
                .TRCENA        (),
                .TRACECLK      (),
                
                // HTM data - Not used
                .HTMDHADDR     (),
                .HTMDHTRANS    (),
                .HTMDHSIZE     (),
                .HTMDHBURST    (),
                .HTMDHPROT     (),
                .HTMDHWDATA    (),
                .HTMDHWRITE    (),
                .HTMDHRDATA    (),
                .HTMDHREADY    (),
                .HTMDHRESP     (),
                
                // Core status
                .HALTED        (HALTED),     // Halted for debug
                .LOCKUP        (LOCKUP),     // Core is locked up
                .BRCHSTAT      (),
                .SLEEPING      (),
                .SLEEPDEEP     (),
                .SLEEPHOLDREQn (1'b1),
                .SLEEPHOLDACKn (),
                .ETMINTNUM     (),           // Current active interrupt
                .ETMINTSTAT    (),           // Interrupt activation status
                .CURRPRI       (),           // Current interrupt priority
                
                // ICODE AHB-lite bus
                .IFLUSH        (1'b0),       // Force icode flush?
                .HREADYI       (hreadyi),
                .HRDATAI       (hrdatai),
                .HRESPI        (hrespi),
                .HTRANSI       (htransi),
                .HSIZEI        (hsizei),
                .HADDRI        (haddri),
                .HBURSTI       (hbursti),
                .HPROTI        (hproti),
                .MEMATTRI      (memattri),
                
                // DCODE AHB-lite bus
                .HMASTERD      (hmasterd),
                .HREADYD       (hreadyd),
                .HRDATAD       (hrdatad),
                .HRESPD        (hrespd),
                .HTRANSD       (htransd),
                .HSIZED        (hsized),
                .HADDRD        (haddrd),
                .HBURSTD       (hburstd),
                .HPROTD        (hprotd),
                .HWRITED       (hwrited),
                .HWDATAD       (hwdatad),
                .MEMATTRD      (memattrd),
                .EXREQD        (exreqd),
                .EXRESPD       (exrespd),
                  
                // System AHB-lite bus
                .HREADYS       (sys_HREADY),
                .HRDATAS       (sys_HRDATA),
                .HRESPS        ({1'b0, sys_HRESP}),
                .HTRANSS       (sys_HTRANS),
                .HSIZES        (sys_HSIZE),
                .HADDRS        (sys_haddr),
                .HBURSTS       (sys_HBURST),
                .HPROTS        (sys_HPROT),
                .HWRITES       (hwrites),
                .HWDATAS       (sys_HWDATA),
                .HMASTLOCKS    (sys_HMASTLOCK),
                .HMASTERS      (hmasters),
                .MEMATTRS      (memattrs),
                .EXREQS        (exreqs),
                .EXRESPS       (exresps)                  
                );
         
      end
      else begin : gen_cm3
         
         // Instantiate obsfucated core
         CORTEXM3INTEGRATIONDS
           u_cm3 (
                  // Clocks
                  .FCLK        (FCLK),
                  .HCLK        (HCLK),
                  .TRACECLKIN  (HCLK),
                  .STCLK       (1'b1), // Not actual clock
                  
                  // Reset
                  .PORESETn    (PORESETn),
                  .SYSRESETn   (CPURESETn),
                  .SYSRESETREQ (SYSRESETREQ),
                      
                  // Interrupts
                  .INTISR      ({224'h0, INTISR[15:0]}), // Only 16 interrupts supported on this model
                  .INTNMI      (INTNMI),
                  .AUXFAULT    (32'h0),
                  
                  // Debug
                  .SWCLKTCK    (SWCLKTCK),
                  .nTRST       (nTRST),
                  .SWDITMS     (SWDITMS),
                  .TDI         (TDI),
                  .TDO         (TDO),
                  .nTDOEN      (nTDOEN),
                  .SWV         (SWV),
                  .SWDO        (SWDO),
                  .SWDOEN      (SWDOEN),
                  .JTAGNSW     (JTAGNSW),
                  
                  // Power management
                  .CDBGPWRUPREQ (cdbgpwrup),
                  .CDBGPWRUPACK (cdbgpwrup),
                  .EDBGRQ       (1'b0),      // What is this?
                  .DBGRESTART   (1'b0),      // Multiproc debug support?
                  .DBGRESTARTED (),
                  .ISOLATEn     (1'b1),      // Isolate core power domain
                  .RETAINn      (1'b1),      // Retain state in power down
                  
                  // Wakeup controller
                  .WICENREQ     (1'b0),      // Wakeup req from PMIC?
                  .WICENACK     (),
                  .WAKEUP       (),
                  
                  // Clock gating/bypass
                  .CGBYPASS     (1'b0),
                  .RSTBYPASS    (1'b0),
                  .GATEHCLK     (),
                  
                  // Miscellaneous
                  .SE            (1'b0),     // Scan enable?
                  .BIGEND        (1'b0),     // Always little endian
                  .STCALIB       (26'h0),    // Systick calib
                  .FIXMASTERTYPE (1'b1),     // Needs to be 1
                  .TSVALUEB      (48'h0),    // TPIU timestamp
                  .DNOTITRANS    (1'b1),     // Enable code mux
                  .MPUDISABLE    (1'b0),
                  .DBGEN         (1'b1),
                  .NIDEN         (1'b1),     // Non-invasive debug
                  .TXEV          (),         // TX event output
                  .RXEV          (1'b0),     // RX event input
                  
                  // Traceport - unused
                  .TRACEDATA     (),
                  .TRCENA        (),
                  .TRACECLK      (),
                      
                  // HTM data - Not used
                  .HTMDHADDR     (),
                  .HTMDHTRANS    (),
                  .HTMDHSIZE     (),
                  .HTMDHBURST    (),
                  .HTMDHPROT     (),
                  .HTMDHWDATA    (),
                  .HTMDHWRITE    (),
                  .HTMDHRDATA    (),
                  .HTMDHREADY    (),
                  .HTMDHRESP     (),
            
                  // Core status
                  .HALTED        (HALTED),     // Halted for debug
                  .LOCKUP        (LOCKUP),     // Core is locked up
                  .BRCHSTAT      (),
                  .SLEEPING      (),
                  .SLEEPDEEP     (),
                  .SLEEPHOLDREQn (1'b1),
                  .SLEEPHOLDACKn (),
                  .ETMINTNUM     (),           // Current active interrupt
                  .ETMINTSTAT    (),           // Interrupt activation status
                  .CURRPRI       (),           // Current interrupt priority
                  
                  // ICODE AHB-lite bus
                  .IFLUSH        (1'b0),       // Force icode flush?
                  .HREADYI       (hreadyi),
                  .HRDATAI       (hrdatai),
                  .HRESPI        (hrespi),
                  .HTRANSI       (htransi),
                  .HSIZEI        (hsizei),
                  .HADDRI        (haddri),
                  .HBURSTI       (hbursti),
                  .HPROTI        (hproti),
                  .MEMATTRI      (memattri),
                  
                  // DCODE AHB-lite bus
                  .HMASTERD      (hmasterd),
                  .HREADYD       (hreadyd),
                  .HRDATAD       (hrdatad),
                  .HRESPD        (hrespd),
                  .HTRANSD       (htransd),
                  .HSIZED        (hsized),
                  .HADDRD        (haddrd),
                  .HBURSTD       (hburstd),
                  .HPROTD        (hprotd),
                  .HWRITED       (hwrited),
                  .HWDATAD       (hwdatad),
                  .MEMATTRD      (memattrd),
                  .EXREQD        (exreqd),
                  .EXRESPD       (exrespd),
                  
                  // System AHB-lite bus
                  .HREADYS       (sys_HREADY),
                  .HRDATAS       (sys_HRDATA),
                  .HRESPS        ({1'b0, sys_HRESP}),
                  .HTRANSS       (sys_HTRANS),
                  .HSIZES        (sys_HSIZE),
                  .HADDRS        (sys_haddr),
                  .HBURSTS       (sys_HBURST),
                  .HPROTS        (sys_HPROT),
                  .HWRITES       (hwrites),
                  .HWDATAS       (sys_HWDATA),
                  .HMASTLOCKS    (sys_HMASTLOCK),
                  .HMASTERS      (hmasters),
                  .MEMATTRS      (memattrs),
                  .EXREQS        (exreqs),
                  .EXRESPS       (exresps)                  
                  );
      end // gen_cm3
   endgenerate
   
endmodule // cm3_core

