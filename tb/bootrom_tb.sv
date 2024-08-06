// NEC uPD7800 testbench: boot ROM
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

`timescale 1us / 1ns

module bootrom_tb();

reg         clk, res;
reg         cp1p, cp1n, cp2p, cp2n;
reg [7:0]   din;
reg [7:0]   dut_db_i;
reg         vbl;

wire [15:0] a;
wire [7:0]  dut_db_o, rom_db, wram_db, vram_db;
wire        dut_rdb, dut_wrb;
wire        rom_ncs, wram_ncs, vram_ncs, cart_ncs;

initial begin
  $timeformat(-6, 0, " us", 1);

`ifndef VERILATOR
  $dumpfile("bootrom_tb.vcd");
  $dumpvars();
`else
  $dumpfile("bootrom_tb.verilator.vcd");
  $dumpvars();
`endif
end

upd7800 dut
  (
   .CLK(clk),
   .CP1_POSEDGE(cp1p),
   .CP1_NEGEDGE(cp1n),
   .CP2_POSEDGE(cp2p),
   .CP2_NEGEDGE(cp2n),
   .RESETB(~res),
   .INT0(1'b0),
   .INT1(1'b0),
   .INT2(vbl),
   .A(a),
   .DB_I(dut_db_i),
   .DB_O(dut_db_o),
   .DB_OE(),
   .M1(),
   .RDB(dut_rdb),
   .WRB(dut_wrb),
   .PA_O(),
   .PB_I(8'b0),
   .PB_O(),
   .PB_OE(),
   .PC_I(8'h01),                // pause switch off
   .PC_O(),
   .PC_OE()
   );

bootrom rom
  (
   .A(a[11:0]),
   .DB(rom_db),
   .nCS(rom_ncs | dut_rdb)
   );

ram #(7, 8) wram
  (
   .CLK(clk),
   .nCE(wram_ncs),
   .nWE(dut_wrb),
   .nOE(wram_ncs | ~dut_wrb),
   .A(a[6:0]),
   .DI(dut_db_o),
   .DO(wram_db)
   );

ram #(10, 8) vram
  (
   .CLK(clk),
   .nCE(vram_ncs),
   .nWE(dut_wrb),
   .nOE(vram_ncs | ~dut_wrb),
   .A(a[9:0]),
   .DI(dut_db_o),
   .DO(vram_db)
   );

always_comb begin
  dut_db_i = 8'hxx;
  if (~rom_ncs)
    dut_db_i = rom_db;
  else if (~wram_ncs)
    dut_db_i = wram_db;
  else if (~vram_ncs)
    dut_db_i = vram_db;
  else if (~cart_ncs)
    dut_db_i = 8'hFF;           // cart is absent
end

assign rom_ncs = |a[15:12];
assign wram_ncs = ~&a[15:7];    // 'hFF80-'hFFFF
assign vram_ncs = (a & ~16'h03ff) != 16'h3000;
assign cart_ncs = ~a[15] | ~wram_ncs | ~vram_ncs;


initial begin
  vbl = 0;
  cp1p = 0;
  cp1n = 0;
  cp2p = 0;
  cp2n = 0;
  res = 1;
  clk = 1;
end

always begin :ckgen
  #0.125 clk = ~clk;
end

always begin :cpgen
  @(posedge clk) cp2n <= 0; cp1p <= 1;
  @(posedge clk) cp1p <= 0; cp1n <= 1;
  @(posedge clk) cp1n <= 0; cp2p <= 1;
  @(posedge clk) cp2p <= 0; cp2n <= 1;
end

wire cp2 = dut.cp2;

always begin :vblgen
  repeat (5000) @(posedge clk) ;
  vbl <= 1'b1;
  repeat (5000) @(posedge clk) ;
  vbl <= 1'b0;
end

initial #0 begin
  #3 @(posedge clk) ;
  res = 0;

  // We're looping until C reaches 0 (inner loop).
  #80 @(posedge clk) ;
  assert(dut.pc == 16'h0016);
  dut.c = 1;

  // We're also looping until B reaches 0 (outer loop).
  #88 @(posedge clk) ;
  assert(dut.pc == 16'h0018);
  dut.b = 0;
  dut.c = 1;
  #2 ;

  // Double 'block' in ClearScreen
  #678 @(posedge clk) ;
  assert(dut.pc == 16'h0a25);
  dut.c -= 8'hF8;
  dut.e += 8'hF8;
  dut.l += 8'hF8;
  #43 @(posedge clk) ;
  assert(dut.pc == 16'h0a26);
  dut.c -= 8'hFD;
  dut.e += 8'hFD;
  dut.l += 8'hFD;

  // Double 'block' in ClearSpriteAttrs
  #1996 @(posedge clk) ;
  assert(dut.pc == 16'h0a25);
  dut.c -= 8'hFC;
  dut.e += 8'hFC;
  dut.l += 8'hFC;
  #43 @(posedge clk) ;
  assert(dut.pc == 16'h0a26);
  dut.c -= 8'hFD;
  dut.e += 8'hFD;
  dut.l += 8'hFD;

  // 16x 'block' in ClearSpritePatterns
  #151 @(posedge clk) ;
  assert(dut.pc == 16'h0a55);
  dut.b -= 8'h0F;
  dut.c -= 8'hF8;
  dut.d += 8'h0F;
  dut.e += 8'hF8;
  dut.h += 8'h0F;
  dut.l += 8'hF8;

  #140000 @(posedge clk) ;

  $finish;
end

endmodule


//////////////////////////////////////////////////////////////////////

module bootrom
  (
   input [11:0]     A,
   output reg [7:0] DB,
   input            nCS
   );

logic [7:0] mem [1 << 12];

initial begin
  $readmemh("bootrom.hex", mem);
end

always_comb begin
  DB = nCS ? 8'hzz : mem[A];
end

endmodule


//////////////////////////////////////////////////////////////////////

module ram
  #(parameter AW,
    parameter DW)
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
    //$display("ram[%x] <= %x", A, D);
    ram[A] <= DI;
  end
end

endmodule


// Local Variables:
// compile-command: "iverilog -g2012 -grelative-include -s bootrom_tb -o bootrom_tb.vvp ../upd7800.sv bootrom_tb.sv && ./bootrom_tb.vvp"
// End:
