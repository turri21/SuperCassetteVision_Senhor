// NEC uPD7800 testbench: boot ROM
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

`timescale 1us / 1ps

// Get to the main loop faster, by shorting loops.
`ifndef VERILATOR
`define FAST_MAIN 1
`endif

module bootrom_tb();

reg         clk, res;
reg         cp1p, cp1n, cp2p, cp2n;
reg [7:0]   dut_db_i;
reg         vbl;

wire [15:0] a;
wire [7:0]  dut_db_o, vram_db;
wire        a_oe;
wire        dut_rdb, dut_wrb;
wire        vram_ncs, cart_ncs;

int         tvbl1 = 5000;
int         tvbl0 = 5000;

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

upd7801 dut
  (
   .CLK(clk),
   .CP1_POSEDGE(cp1p),
   .CP1_NEGEDGE(cp1n),
   .CP2_POSEDGE(cp2p),
   .CP2_NEGEDGE(cp2n),
   .INIT_SEL_BOOT('0),
   .INIT_ADDR('0),
   .INIT_DATA('0),
   .INIT_VALID('0),
   .RESETB(~res),
   .INT0(1'b0),
   .INT1(1'b0),
   .INT2(vbl),
   .A(a),
   .A_OE(a_oe),
   .DB_I(dut_db_i),
   .DB_O(dut_db_o),
   .DB_OE(),
   .WAITB('1),
   .M1(),
   .RDB(dut_rdb),
   .WRB(dut_wrb),
   .PA_O(),
   .PB_I(8'hff),                // no buttons pressed
   .PB_O(),
   .PB_OE(),
   .PC_I(8'h01),                // pause switch off
   .PC_O(),
   .PC_OE()
   );

initial
  $readmemh("bootrom.hex", dut.rom.mem);

ram #(10, 8) vram
  (
   .CLK(clk),
   .nCE(vram_ncs),
   .nWE(dut_wrb),
   .nOE(vram_ncs | dut_rdb),
   .A(a[9:0]),
   .DI(dut_db_o),
   .DO(vram_db)
   );

always_comb begin
  if (~vram_ncs)
    dut_db_i = vram_db;
  else
    dut_db_i = 8'hFF;           // cart is absent
end

assign vram_ncs = ~(a_oe & ~a[15]);

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
  #0.0625 clk = ~clk;
end

always begin :cpgen
  @(posedge clk) cp2n <= 0; cp1p <= 1;
  @(posedge clk) cp1p <= 0; cp1n <= 1;
  @(posedge clk) cp1n <= 0; cp2p <= 1;
  @(posedge clk) cp2p <= 0; cp2n <= 1;
end

wire cp2 = dut.core.cp2;

initial begin :vblgen
  @(negedge res) ;
  forever begin
    repeat (tvbl0) @(posedge clk) ;
    vbl = 1'b1;
    repeat (tvbl1) @(posedge clk) ;
    vbl = 1'b0;
  end
end

task normal_video();
  begin
    // Normal video timing
    tvbl1 = 8 * 1558;
    tvbl0 = 8 * 15109;
  end
endtask


`ifdef FAST_MAIN
initial #0 begin
  #2 @(posedge clk) ;
  res = 0;

  // We're looping until C reaches 0 (inner loop).
  #40 @(posedge clk) ;
  assert(dut.core.pc == 16'h0016);
  dut.core.c = 1;

  // We're also looping until B reaches 0 (outer loop).
  #40 @(posedge clk) ;
  assert(dut.core.pc == 16'h0018);
  dut.core.b = 0;
  dut.core.c = 1;
  #1 ;

  // Double 'block' in ClearScreen
  #340 @(posedge clk) ;
  assert(dut.core.pc == 16'h0a25);
  dut.core.c -= 8'hF8;
  dut.core.e += 8'hF8;
  dut.core.l += 8'hF8;
  #27 @(posedge clk) ;
  assert(dut.core.pc == 16'h0a26);
  dut.core.c -= 8'hFD;
  dut.core.e += 8'hFD;
  dut.core.l += 8'hFD;

  // Double 'block' in ClearSpriteAttrs
  #1005 @(posedge clk) ;
  assert(dut.core.pc == 16'h0a25);
  dut.core.c -= 8'hFC;
  dut.core.e += 8'hFC;
  dut.core.l += 8'hFC;
  #27 @(posedge clk) ;
  assert(dut.core.pc == 16'h0a26);
  dut.core.c -= 8'hFD;
  dut.core.e += 8'hFD;
  dut.core.l += 8'hFD;

  // 16x 'block' in ClearSpritePatterns
  #79 @(posedge clk) ;
  assert(dut.core.pc == 16'h0a55);
  dut.core.b -= 8'h0F;
  dut.core.c -= 8'hF8;
  dut.core.d += 8'h0F;
  dut.core.e += 8'hF8;
  dut.core.h += 8'h0F;
  dut.core.l += 8'hF8;

  normal_video();

  #(140e3) @(posedge clk) ;
  $finish;
end

`else // FAST_MAIN

initial #0 begin
  normal_video();

  #2 @(posedge clk) ;
  res = 0;

  #(500e3) @(posedge clk) ;

  $finish;
end

`endif

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

reg [DW-1:0] mem [0:((1 << AW) - 1)];
reg [DW-1:0] dor;

// Undefined RAM contents make simulation eventually die.
initial begin
int i;
  for (i = 0; i < (1 << AW); i++)
    mem[i] = 0;
end

always @(posedge CLK)
  dor <= mem[A];

assign DO = ~(nCE | nOE) ? dor : {DW{1'bz}};

always @(negedge CLK) begin
  if (~(nCE | nWE)) begin
    //$display("ram[%x] <= %x", A, D);
    mem[A] <= DI;
  end
end

endmodule


// Local Variables:
// compile-command: "iverilog -g2012 -grelative-include -s bootrom_tb -o bootrom_tb.vvp ../upd7800.sv ../upd7801.sv bootrom_tb.sv && ./bootrom_tb.vvp"
// End:
