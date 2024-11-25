// Cartridge ROM
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

module cart_rom
  (
   input             CLK,

   input             INIT_SEL,
   input [16:0]      INIT_ADDR,
   input [7:0]       INIT_DATA,
   input             INIT_VALID,

   output reg [4:0]  SIZE_LOG2,
   output reg [31:0] CKSUM,

   input [16:0]      A,
   output reg [7:0]  DB,
   input             CSB
   );

logic [7:0] mem [1 << 17];

logic [31:0] cksum;
logic [4:0]  size_log2;
logic        init_sel_d;

always @(posedge CLK) begin
  DB <= CSB ? 8'hxx : mem[A];
end

always @(posedge CLK) begin
  if (INIT_SEL & INIT_VALID) begin
    mem[INIT_ADDR] = INIT_DATA;
  end
end

function [4:0] size_log2_from_addr(input [16:0] addr);
  size_log2_from_addr = 5'd0;
  if (~|addr[16:13] & &addr[12:0])
    size_log2_from_addr = 5'd13; // 8K
  else if (~|addr[16:14] & &addr[13:0])
    size_log2_from_addr = 5'd14;
  else if (~|addr[16:15] & &addr[14:0])
    size_log2_from_addr = 5'd15;
  else if (~|addr[16:16] & &addr[15:0])
    size_log2_from_addr = 5'd16;
  else if (&addr[16:0])
    size_log2_from_addr = 5'd17; // 128K
endfunction

// Compute size and checksum
//
// See /doc/scan-rom.py for the (trivial) checksum algorithm.

always @(posedge CLK) begin
  if (INIT_SEL & ~init_sel_d) begin
    size_log2 <= 0;
    cksum <= 0;
  end
  else if (INIT_SEL & INIT_VALID) begin
    size_log2 <= size_log2_from_addr(INIT_ADDR);
    cksum <= cksum + 32'(INIT_DATA);
  end
  else if (~INIT_SEL & init_sel_d) begin
    SIZE_LOG2 <= size_log2;
    CKSUM <= cksum;
  end

  init_sel_d <= INIT_SEL;
end


endmodule
