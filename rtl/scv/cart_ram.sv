// Cartridge RAM
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

module cart_ram
  (
   input        CLK,

   //input [12:0] INIT_ADDR,
   //input [7:0]  INIT_DATA,
   //input        INIT_VALID,

   input [4:0]  CFG_AW,

   input [12:0] A,
   input [7:0]  DI,
   output [7:0] DO,
   input        nCE,
   input        nWE,
   input        nOE
   );

logic [7:0] mem [1 << 13];
logic [12:0] a;
logic [7:0]  dor;

assign a[12:0] = A & ((13'd1 << CFG_AW) - 1'd1);

always @(posedge CLK) begin
  dor <= mem[a];
  if (~(nCE | nWE))
    mem[a] <= DI;
end

//always @(posedge CLK) begin
//  if (INIT_VALID) begin
//    mem[INIT_ADDR] = INIT_DATA;
//  end
//end

assign DO = (nCE | nOE) ? 8'hxx : dor;

endmodule
