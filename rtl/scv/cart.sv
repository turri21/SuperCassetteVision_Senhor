// Cartridge slot and cartridge
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

import scv_pkg::mapper_t;

module cart
  (
   input            CLK,

   input            INIT_SEL,
   input [16:0]     INIT_ADDR,
   input [7:0]      INIT_DATA,
   input            INIT_VALID,

   input            mapper_t MAPPER,
   
   input [14:0]     A,
   input [7:0]      DB_I,
   output reg [7:0] DB_O,
   output           DB_OE,
   input            RDB,
   input            WRB,
   input            CSB,
   input [6:5]      PC
   );

mapper_t id_mapper;

wire [4:0]  rom_size_log2;
wire [31:0] rom_cksum;
wire [16:0] rom_a;
wire [7:0]  rom_db_o;
wire        rom_db_oe;
wire        rom_csb;

wire [12:0] ram_a;
wire [7:0]  ram_db_o;
wire        ram_db_oe;
wire        ram_csb, ram_nwe, ram_noe;

cart_id id
  (
   .CLK(CLK),

   .ROM_SIZE_LOG2(rom_size_log2),
   .ROM_CKSUM(rom_cksum),

   .IN_MAPPER(MAPPER),
   .OUT_MAPPER(id_mapper)
   );

cart_mapper mapper
  (
   .CLK(CLK),

   .MAPPER(id_mapper),

   .A(A),
   .RDB(RDB),
   .WRB(WRB),
   .CSB(CSB),
   .PC(PC),

   .ROM_A(rom_a),
   .ROM_CSB(rom_csb),

   .RAM_A(ram_a),
   .RAM_CSB(ram_csb)
   );

assign rom_db_oe = ~rom_csb;

cart_rom rom
  (
   .CLK(CLK),

   .INIT_SEL(INIT_SEL),
   .INIT_ADDR(INIT_ADDR),
   .INIT_DATA(INIT_DATA),
   .INIT_VALID(INIT_VALID),

   .SIZE_LOG2(rom_size_log2),
   .CKSUM(rom_cksum),

   .A(rom_a),
   .DB(rom_db_o),
   .CSB(rom_csb)
   );

assign ram_nwe = WRB;
assign ram_noe = RDB;

cart_ram ram
  (
   .CLK(CLK),

   .A(ram_a),
   .DI(DB_I),
   .DO(ram_db_o),
   .nCE(ram_csb),
   .nWE(ram_nwe),
   .nOE(ram_noe)
   );

assign ram_db_oe = ~(ram_csb | ram_noe);

always_comb begin
  DB_O = 8'hxx;
  if (rom_db_oe)
    DB_O = rom_db_o;
  else if (ram_db_oe)
    DB_O = ram_db_o;
end

assign DB_OE = rom_db_oe | ram_db_oe;

endmodule
