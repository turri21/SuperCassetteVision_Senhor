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
   input [4:0]      CFG_RAM_AW,
   
   input [14:0]     A,
   input [7:0]      DB_I,
   output reg [7:0] DB_O,
   output           DB_OE,
   input            RDB,
   input            WRB,
   input            nCS,
   input [6:5]      PC
   );

wire [7:0] rom_db_o;
wire       rom_db_oe;
wire       rom_ncs;

wire [7:0] ram_db_o;
wire       ram_db_oe;
wire       ram_en, ram_nce, ram_nwe, ram_noe;

assign rom_ncs = nCS | ram_en;
assign rom_db_oe = ~rom_ncs;

cart_rom rom
  (
   .CLK(CLK),

   .INIT_ADDR(INIT_ADDR),
   .INIT_DATA(INIT_DATA),
   .INIT_VALID(INIT_VALID),

   .CFG_AW(CFG_ROM_AW),

   .A(A),
   .DB(rom_db_o),
   .nCS(rom_ncs)
   );

assign ram_en = PC[5] & &A[14:13];
assign ram_nce = nCS | ~ram_en;
assign ram_nwe = WRB;
assign ram_noe = RDB;

cart_ram ram
  (
   .CLK(CLK),

   .CFG_AW(CFG_RAM_AW),

   .A(A[12:0]),
   .DI(DB_I),
   .DO(ram_db_o),
   .nCE(ram_nce),
   .nWE(ram_nwe),
   .nOE(ram_noe)
   );

assign ram_db_oe = ~(ram_nce | ram_noe);

always_comb begin
  DB_O = 8'hxx;
  if (rom_db_oe)
    DB_O = rom_db_o;
  else if (ram_db_oe)
    DB_O = ram_db_o;
end

assign DB_OE = rom_db_oe | ram_db_oe;

endmodule
