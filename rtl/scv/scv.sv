// Super Cassette Vision - an emulator
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

// References:
// . https://forums.atariage.com/topic/130365-atari-7800-vs-epoch-super-cassette-vision/ - [takeda.txt]
// . http://takeda-toshiya.my.coocan.jp/scv/index.html


`timescale 1us / 1ns

import scv_pkg::*;

module scv
  (
   input         CLK, // clock (video XTAL * 2)
   input         RESB,

   input         ROMINIT_SEL_BOOT,
   input         ROMINIT_SEL_CHR,
   input [11:0]  ROMINIT_ADDR,
   input [7:0]   ROMINIT_DATA,
   input         ROMINIT_VALID,

   input         hmi_t HMI,

   output        VID_PCE,
   output        VID_DE,
   output        VID_HS,
   output        VID_VS,
   output [23:0] VID_RGB
   );

wire        cp1p, cp1n, cp2p, cp2n;
wire        vdc_ce;

wire [15:0] cpu_a;
reg [7:0]   cpu_db;
wire [7:0]  cpu_db_o;
wire        cpu_db_oe;
wire        cpu_rdb, cpu_wrb;

wire [7:0]  rom_db;
wire        rom_ncs;

wire        wram_ncs;
wire        wram_db_oe;
wire [7:0]  wram_db;

wire [7:0]  vdc_db_o;
wire        vdc_db_oe;
wire        vdc_ncs;
wire [11:0] vaa, vba;
wire [7:0]  vad_i, vad_o, vbd_i, vbd_o;
wire        nvard, nvawr, nvbrd, nvbwr;
wire        vbl;
wire        de, hs, vs;
wire [23:0] rgb;

wire        cart_ncs;
wire        rom_db_oe, cart_db_oe;

wire [7:0]  pao, pbi, pci, pco;

clkgen clkgen
  (
   .CLK(CLK),
   .CP1_POSEDGE(cp1p),
   .CP1_NEGEDGE(cp1n),
   .CP2_POSEDGE(cp2p),
   .CP2_NEGEDGE(cp2n),
   .VDC_CE(vdc_ce)
   );

upd7800 cpu
  (
   .CLK(CLK),
   .CP1_POSEDGE(cp1p),
   .CP1_NEGEDGE(cp1n),
   .CP2_POSEDGE(cp2p),
   .CP2_NEGEDGE(cp2n),
   .RESETB(RESB),
   .INT0(1'b0),
   .INT1(1'b0),
   .INT2(vbl),
   .A(cpu_a),
   .DB_I(cpu_db),
   .DB_O(cpu_db_o),
   .DB_OE(cpu_db_oe),
   .M1(),
   .RDB(cpu_rdb),
   .WRB(cpu_wrb),
   .PA_O(pao),
   .PB_I(pbi),
   .PB_O(),
   .PB_OE(),
   .PC_I(pci),
   .PC_O(pco),
   .PC_OE()
   );

bootrom rom
  (
`ifndef SCV_BOOTROM_INIT_FROM_HEX
   .INIT_CLK(CLK),
   .INIT_ADDR(ROMINIT_ADDR[11:0]),
   .INIT_DATA(ROMINIT_DATA),
   .INIT_VALID(ROMINIT_SEL_BOOT & ROMINIT_VALID),
`endif
   .A(cpu_a[11:0]),
   .DB(rom_db),
   .nCS(rom_ncs)
   );

wram wram
  (
   .CLK(CLK),
   .nCE(wram_ncs),
   .nWE(cpu_wrb),
   .nOE(~wram_db_oe),
   .A(cpu_a[6:0]),
   .DI(cpu_db),
   .DO(wram_db)
   );

epochtv1 vdc
  (
   .CLK(CLK),
   .CE(vdc_ce),

   //.ROMINIT_SEL_CHR(ROMINIT_SEL_CHR),
   //.ROMINIT_ADDR(ROMINIT_ADDR),
   //.ROMINIT_DATA(ROMINIT_DATA),
   //.ROMINIT_VALID(ROMINIT_VALID),

   .A(cpu_a[12:0]),
   .DB_I(cpu_db),
   .DB_O(vdc_db_o),
   .DB_OE(vdc_db_oe),
   .RDB(cpu_rdb),
   .WRB(cpu_wrb),
   .CSB(vdc_ncs),

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

   .VBL(vbl),
   .DE(de),
   .HS(hs),
   .VS(vs),
   .RGB(rgb)
   );

dpram #(.DWIDTH(8), .AWIDTH(12)) vrama
  (
   .CLK(CLK),

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
   .CLK(CLK),

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

hmi2key hmi2key
  (
   .HMI(HMI),

   .KEY_COL(pao),
   .KEY_ROW(pbi),
   .PAUSE(pci[0])
   );

assign rom_ncs = |cpu_a[15:12];
assign wram_ncs = ~&cpu_a[15:7];    // 'hFF80-'hFFFF
assign vdc_ncs = (cpu_a & ~16'h1fff) != 16'h2000;
assign cart_ncs = ~cpu_a[15] | ~wram_ncs | ~vdc_ncs;

assign rom_db_oe = ~(rom_ncs | cpu_rdb);
assign wram_db_oe = ~(wram_ncs | cpu_rdb);
assign cart_db_oe = ~(cart_ncs | cpu_rdb);

always_comb begin
  cpu_db = 8'hxx;
  if (cpu_db_oe)
    cpu_db = cpu_db_o;
  else if (rom_db_oe)
    cpu_db = rom_db;
  else if (wram_db_oe)
    cpu_db = wram_db;
  else if (vdc_db_oe)
    cpu_db = vdc_db_o;
  else if (cart_db_oe)
    cpu_db = 8'hFF;           // cart is absent
end

assign pbi = 8'hff;             // no buttons pressed
assign pci[7:1] = 0;            // unused

assign VID_PCE = vdc_ce;
assign VID_DE = de;
assign VID_HS = hs;
assign VID_VS = vs;
assign VID_RGB = rgb;

endmodule

//////////////////////////////////////////////////////////////////////

module clkgen
  (
   // CLK: 2 * video XTAL = 2 * 14.318181 MHz
   input  CLK,

   // 2-phase CPU clock: CLK / 14 = 2.045454 MHz
   output CP1_POSEDGE, // clock phase 1, +ve edge
   output CP1_NEGEDGE, //  "             -ve edge
   output CP2_POSEDGE, // clock phase 2, +ve edge
   output CP2_NEGEDGE, //  "             -ve edge

   // VDC clock: CLK / 7 = 4.090909 MHz
   output VDC_CE
   );

reg [3:0] ccnt;

initial begin
  ccnt = 0;
end

always_ff @(posedge CLK) begin
  ccnt <= (ccnt == 4'd13) ? 0 : ccnt + 1'd1;
end

assign CP2_NEGEDGE = ccnt == 4'd0;
assign CP1_POSEDGE = ccnt == 4'd2;
assign CP1_NEGEDGE = ccnt == 4'd4;
assign CP2_POSEDGE = ccnt == 4'd6;

assign VDC_CE = (ccnt == 4'd2) | (ccnt == 4'd9);

endmodule

//////////////////////////////////////////////////////////////////////

module bootrom
  (
`ifndef SCV_BOOTROM_INIT_FROM_HEX
   input            INIT_CLK,
   input [11:0]     INIT_ADDR,
   input [7:0]      INIT_DATA,
   input            INIT_VALID,
`endif
   input [11:0]     A,
   output reg [7:0] DB,
   input            nCS
   );

logic [7:0] mem [1 << 12];

`ifdef SCV_BOOTROM_INIT_FROM_HEX
initial begin
  $readmemh("bootrom.hex", mem);
end
`endif

always_comb begin
  DB = nCS ? 8'hzz : mem[A];
end

`ifndef SCV_BOOTROM_INIT_FROM_HEX
always @(posedge INIT_CLK) begin
  if (INIT_VALID) begin
    mem[INIT_ADDR] = INIT_DATA;
  end
end
`endif

endmodule

//////////////////////////////////////////////////////////////////////

module wram
  #(parameter AW=7,
    parameter DW=8)
  (
   input           CLK,
   input           nCE,
   input           nWE,
   input           nOE,
   input [AW-1:0]  A,
   input [DW-1:0]  DI,
   output [DW-1:0] DO
   );

reg [DW-1:0] ram [0:((1 << AW) - 1)];
reg [DW-1:0] dor;

// Undefined RAM contents make simulation eventually die.
initial begin
int i;
  for (i = 0; i < (1 << AW); i++)
    ram[i] = 0;
end

always @(posedge CLK)
  dor <= ram[A];

assign DO = ~(nCE | nOE) ? dor : {DW{1'bz}};

always @(negedge CLK) begin
  if (~(nCE | nWE)) begin
    ram[A] <= DI;
  end
end

endmodule
