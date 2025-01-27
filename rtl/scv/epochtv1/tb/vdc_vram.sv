// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

`timescale 1us / 1ps

module vdc_vram
  (
   input         clk,
   input         ce,

   input [12:0]  a,
   input [7:0]   db_i,
   output [7:0]  db_o,
   input         rdb,
   input         wrb,
   input         csb,

   output        de,
   output        hs,
   output        vs,
   output [23:0] rgb
   );

wire [11:0] vaa, vba;
wire [7:0]  vad_i, vad_o, vbd_i, vbd_o;
wire        nvard, nvawr, nvbrd, nvbwr;

epochtv1 vdc
  (
   .CLK(clk),
   .CE(ce),

   .CFG_PALETTE('0),

   .A(a),
   .DB_I(db_i),
   .DB_O(db_o),
   .DB_OE(),
   .RDB(rdb),
   .WRB(wrb),
   .CSB(csb),

   .VAA(vaa),
   .VAD_I(vad_i),
   .VAD_O(vad_o),
   .nVARD(nvard),
   .nVAWR(nvawr),

   .VBA(vba),
   .VBD_I(vbd_i),
   .VBD_O(vbd_o),
   .nVBRD(nvbrd),
   .nVBWR(nvbwr),

   .DE(de),
   .HS(hs),
   .VS(vs),
   .RGB(rgb)
   );

dpram #(.DWIDTH(8), .AWIDTH(12)) vrama
  (
   .CLK(clk),

   .nCE(nvard & nvawr),
   .nWE(nvawr),
   .nOE(nvard),
   .A(vaa),
   .DI(vad_o),
   .DO(vad_i),

   .nCE2(1'b1),
   .nWE2(1'b1),
   .nOE2(1'b1),
   .A2(),
   .DI2(),
   .DO2()
   );

dpram #(.DWIDTH(8), .AWIDTH(12)) vramb
  (
   .CLK(clk),

   .nCE(nvbrd & nvbwr),
   .nWE(nvbwr),
   .nOE(nvbrd),
   .A(vba),
   .DI(vbd_o),
   .DO(vbd_i),

   .nCE2(1'b1),
   .nWE2(1'b1),
   .nOE2(1'b1),
   .A2(),
   .DI2(),
   .DO2()
   );

endmodule
