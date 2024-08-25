// Cartridge slot and cartridge
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

   input [4:0]      CFG_AW,

   input [14:0]     A,
   output reg [7:0] DB,
   input            nCS
   );

logic [7:0] mem [1 << 17];
logic [16:0] a;

assign a[16:15] = 0;
assign a[14:0] = A & ((15'd1 << CFG_AW) - 1'd1);

always @(posedge CLK) begin
  DB <= nCS ? 8'hxx : mem[a];
end

always @(posedge CLK) begin
  if (INIT_VALID) begin
    mem[INIT_ADDR] = INIT_DATA;
  end
end


endmodule
