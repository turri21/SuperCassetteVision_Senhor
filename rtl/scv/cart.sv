// Cartridge slot and cartridge
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

module cart
  (
   input            CLK,

   input [16:0]     INIT_ADDR,
   input [7:0]      INIT_DATA,
   input            INIT_VALID,

   input [4:0]      CFG_ROM_AW,
   
   input [14:0]     A,
   output reg [7:0] DB,
   input            nCS
   );

cart_rom rom
  (
   .CLK(CLK),

   .INIT_ADDR(INIT_ADDR),
   .INIT_DATA(INIT_DATA),
   .INIT_VALID(INIT_VALID),

   .CFG_AW(CFG_ROM_AW),

   .A(A),
   .DB(DB),
   .nCS(nCS)
   );

endmodule
