// Download manager for ROM initialization
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

module rominit
  (
   input         CLK_SYS,

   input         IOCTL_DOWNLOAD,
   input [15:0]  IOCTL_INDEX,
   input         IOCTL_WR,
   input [26:0]  IOCTL_ADDR,
   input [7:0]   IOCTL_DOUT,
   output        IOCTL_WAIT,

   output        ROMINIT_ACTIVE,
   output        ROMINIT_SEL_BOOT, 
   output        ROMINIT_SEL_CHR,
   output        ROMINIT_SEL_APU,
   output        ROMINIT_SEL_CART,
   output [16:0] ROMINIT_ADDR,
   output [7:0]  ROMINIT_DATA,
   output        ROMINIT_VALID
   );

reg [16:0] addr;

wire [5:0] index_menusub = IOCTL_INDEX[5:0];
wire [7:0] index_file_ext = IOCTL_INDEX[13:6];

wire       load_boot = (index_menusub == 0);
wire       load_cart = (index_menusub == 1);

assign IOCTL_WAIT = 0;

assign ROMINIT_ACTIVE = IOCTL_DOWNLOAD;
assign ROMINIT_SEL_BOOT = ROMINIT_ACTIVE & load_boot & (IOCTL_ADDR < 24'h1000);
assign ROMINIT_SEL_CHR = ROMINIT_ACTIVE & load_boot & (IOCTL_ADDR < 24'h1400) & ~ROMINIT_SEL_BOOT;
assign ROMINIT_SEL_APU = ROMINIT_ACTIVE & load_boot & (IOCTL_ADDR < 24'h1800) & ~ROMINIT_SEL_CHR;
assign ROMINIT_SEL_CART = ROMINIT_ACTIVE & load_cart;
assign ROMINIT_DATA = IOCTL_DOUT;
assign ROMINIT_VALID = IOCTL_DOWNLOAD & IOCTL_WR & ~IOCTL_WAIT;
assign ROMINIT_ADDR = addr;

always_comb begin
  addr = 0;
  if (ROMINIT_SEL_BOOT)
    addr[11:0] = IOCTL_ADDR[11:0]; // 4KB
  else if (ROMINIT_SEL_CHR)
    addr[9:0] = IOCTL_ADDR[9:0]; // 1KB
  else if (ROMINIT_SEL_APU)
    addr[9:0] = IOCTL_ADDR[9:0]; // 1KB
  else if (ROMINIT_SEL_CART)
    addr[16:0] = IOCTL_ADDR[16:0];
end

endmodule
