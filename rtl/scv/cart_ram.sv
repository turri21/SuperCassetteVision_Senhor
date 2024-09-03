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

   input [12:0] A,
   input [7:0]  DI,
   output [7:0] DO,
   input        nCE,
   input        nWE,
   input        nOE
   );

logic [7:0] mem [1 << 13];
logic [7:0]  dor;

always @(posedge CLK) begin
  dor <= mem[A];
  if (~(nCE | nWE))
    mem[A] <= DI;
end

//always @(posedge CLK) begin
//  if (INIT_VALID) begin
//    mem[INIT_ADDR] = INIT_DATA;
//  end
//end

assign DO = (nCE | nOE) ? 8'hxx : dor;

endmodule
