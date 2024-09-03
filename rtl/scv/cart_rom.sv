// Cartridge ROM
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

module cart_rom
  (
   input            CLK,

   input [16:0]     INIT_ADDR,
   input [7:0]      INIT_DATA,
   input            INIT_VALID,

   input [16:0]     A,
   output reg [7:0] DB,
   input            CSB
   );

logic [7:0] mem [1 << 17];

always @(posedge CLK) begin
  DB <= CSB ? 8'hxx : mem[A];
end

always @(posedge CLK) begin
  if (INIT_VALID) begin
    mem[INIT_ADDR] = INIT_DATA;
  end
end


endmodule
