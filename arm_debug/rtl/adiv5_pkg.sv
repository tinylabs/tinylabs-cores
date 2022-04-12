/**
 *  Common definitions for connecting IP to host FIFOs.
 * 
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */

package adiv5_pkg;

   // ADIv5 CMD / RESP
   parameter ADIv5_CMD_WIDTH = 36;
   parameter ADIv5_RESP_WIDTH = 35;

   // SWD PHY CMD / RESP
   parameter SWD_CMD_WIDTH = 82;
   parameter SWD_RESP_WIDTH = 43;
   
   // JTAG PHY CMD / RESP
   parameter JTAG_CMD_WIDTH = 79;
   parameter JTAG_RESP_WIDTH = 70;

   typedef enum logic [2:0] 
     {
      STAT_FAULT     = 3'b001,
      STAT_TIMEOUT   = 3'b010,
      STAT_OK        = 3'b100,
      STAT_NOCONNECT = 3'b111
   } adiv5_stat_t;
   
   // Command encoding
   typedef struct packed {
      logic [31:0] data;
      logic [1:0]  addr;
      logic [0:0]  APnDP;
      logic [0:0]  RnW;
   } adiv5_cmd_t;

   // Response encoding
   typedef struct packed {
      logic [31:0] data;
      logic [2:0]  stat;
   } adiv5_resp_t;

   // DP addresses
   typedef enum logic [1:0]
     {
      DP_ADDR_DPIDR_ABRT  = 2'b00,
      DP_ADDR_CTRL_STAT   = 2'b01,
      DP_ADDR_SELECT      = 2'b10,
      DP_ADDR_RDBUF       = 2'b11
      } adiv5_dp_addr;
   
   // AP addresses
   typedef enum logic [5:0]
     {
      AP_ADDR_CSW = 6'b000000,  // CSW - Control/Status word
      AP_ADDR_TAR = 6'b000001,  // TAR - Transfer Address register
      AP_ADDR_DRW = 6'b000011,  // DRW - Data Read/Write
      AP_ADDR_BD0 = 6'b000100,  // BD0 - Banked data 0
      AP_ADDR_BD1 = 6'b000101,  // BD1 - Banked data 1
      AP_ADDR_BD2 = 6'b000110,  // BD2 - Banked data 2
      AP_ADDR_BD4 = 6'b000111,  // BD3 - Banked data 3
      AP_ADDR_MBT = 6'b001000,  // MBT - Memory barrier transfer
      AP_ADDR_CFG = 6'b111101,  // CFG - Configuration register
      AP_ADDR_BASE = 6'b111110, // BASE - Debug base register
      AP_ADDR_IDR = 6'b111111   // IDR - Identification register
      } adiv5_ap_addr;

   // CSW fields
   typedef enum logic [1:0]
     {
      CSW_INC_NONE   = 2'b00,
      CSW_INC_SINGLE = 2'b01,
      CSW_INC_PACKED = 2'b10
      } csw_f_inc;

   typedef enum logic [2:0] 
     {
      CSW_WIDTH_BYTE    = 3'b000,
      CSW_WIDTH_HALF    = 3'b001,
      CSW_WIDTH_WORD    = 3'b010,
      CSW_WIDTH_64BIT   = 3'b011,
      CSW_WIDTH_128BIT  = 3'b100,
      CSW_WIDTH_256BIT  = 3'b101
      } csw_f_width;

   // ADIv5 registers
   typedef struct packed {
      logic [0:0]   dbg_enabled; // 31 RW - Always set to 1
      logic [6:0]   prot;        // 30:24 RW - Mem protection - 4 bits defined in ahb3lite_pkg
      logic [0:0]   spiden;      // 23 RO - Secure bus access
      logic [6:0]   res;         // 22:16 - Reserved
      logic [0:0]   mte;         // 15 RW - Memory tagging
      logic [2:0]   mte_access;  // 14:12 RW  - Used in conjunction with prot
      logic [3:0]   mode;        // 11:8 RW/RO - Basic = 1 (RO if only one defined)
      logic [0:0]   tip;         // 7 RO - Transfer in progress
      logic [0:0]   memap_en;    // 6 - Enable mem-ap
      csw_f_inc     autoinc;     // 5:4 RW - Auto increment address on success
      logic [0:0]   res1;        // 3 RO Reserved
      csw_f_width   width;       // 2:0 RW - Access width
   } adiv5_ap_csw;

   typedef struct packed {
      logic [7:0]  apsel;
      logic [15:0] res;
      logic [3:0]  apbank;
      logic [3:0]  dpbank;
   } adiv5_dp_sel;

   // Helper functions
   function logic [0:0] bank_match(adiv5_dp_sel sel, adiv5_ap_addr addr);
      return (addr[5:2] == sel.apbank);
   endfunction // bank_match
      
   // Function for generating ADIv5 commands
   function adiv5_cmd_t AP_REG_WRITE(adiv5_ap_addr addr, logic [31:0] data);
      AP_REG_WRITE.addr = addr[1:0];
      AP_REG_WRITE.data = data;
      AP_REG_WRITE.APnDP = 1;
      AP_REG_WRITE.RnW = 0;      
   endfunction // AP_REG_WRITE

   function adiv5_cmd_t AP_REG_READ(adiv5_ap_addr addr);
      AP_REG_READ.addr = addr[1:0];
      AP_REG_READ.APnDP = 1;
      AP_REG_READ.RnW = 1;
   endfunction // AP_REG_READ

   function adiv5_cmd_t DP_REG_READ(adiv5_dp_addr addr);
      DP_REG_READ.addr = addr[1:0];
      DP_REG_READ.APnDP = 0;
      DP_REG_READ.RnW = 1;      
   endfunction // DP_REG_READ

   function adiv5_cmd_t DP_REG_WRITE(adiv5_dp_addr addr, logic [31:0] data);
      DP_REG_WRITE.addr = addr[1:0];
      DP_REG_WRITE.data = data;
      DP_REG_WRITE.APnDP = 0;
      DP_REG_WRITE.RnW = 0;      
   endfunction // DP_REG_WRITE

  
endpackage
