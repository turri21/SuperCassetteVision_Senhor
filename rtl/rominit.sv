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

   output        ROMINIT_SEL_BOOT, 
   output        ROMINIT_SEL_CHR,
   output [11:0] ROMINIT_ADDR,
   output [7:0]  ROMINIT_DATA,
   output        ROMINIT_VALID
   );

reg [11:0] addr;

assign IOCTL_WAIT = 0;

assign ROMINIT_SEL_BOOT = (IOCTL_ADDR < 24'h1000);
assign ROMINIT_SEL_CHR = (IOCTL_ADDR < 24'h1400) & ~ROMINIT_SEL_BOOT;
assign ROMINIT_DATA = IOCTL_DOUT;
assign ROMINIT_VALID = IOCTL_DOWNLOAD & IOCTL_WR & ~IOCTL_WAIT;
assign ROMINIT_ADDR = addr;

always_comb begin
  addr = 0;
  if (ROMINIT_SEL_BOOT)
    addr[11:0] = IOCTL_ADDR[11:0];
  else if (ROMINIT_SEL_CHR)
    addr[9:0] = IOCTL_ADDR[9:0];
end

endmodule
