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

wire [15:0] a;
wire [7:0]  dut_db_o, rom_db, ram_db;
wire        dut_rdb, dut_wrb;
wire        rom_ncs, ram_ncs, cart_ncs;

initial begin
  $timeformat(-6, 0, " us", 1);

  $dumpfile("tb/bootrom_tb.vcd");
  $dumpvars();
end

upd7800 dut
  (
   .CLK(clk),
   .CP1_POSEDGE(cp1p),
   .CP1_NEGEDGE(cp1n),
   .CP2_POSEDGE(cp2p),
   .CP2_NEGEDGE(cp2n),
   .RESETB(~res),
   .A(a),
   .DB_I(dut_db_i),
   .DB_O(dut_db_o),
   .DB_OE(),
   .M1(),
   .RDB(dut_rdb),
   .WRB(dut_wrb)
   );

bootrom rom
  (
   .A(a[11:0]),
   .DB(rom_db),
   .nCS(rom_ncs | dut_rdb)
   );

ram #(7, 8) ram
  (
   .CLK(clk),
   .nCE(ram_ncs),
   .nWE(dut_wrb),
   .nOE(ram_ncs | ~dut_wrb),
   .A(a[6:0]),
   .DI(dut_db_o),
   .DO(ram_db)
   );

always_comb begin
  dut_db_i = 8'hxx;
  if (~rom_ncs)
    dut_db_i = rom_db;
  else if (~ram_ncs)
    dut_db_i = ram_db;
  else if (~cart_ncs)
    dut_db_i = 8'hFF;           // cart is absent
end

assign rom_ncs = |a[15:12];
assign ram_ncs = ~&a[15:7];    // 'hFF80-'hFFFF
assign cart_ncs = ~a[15] | ~ram_ncs;


initial begin
  cp1p = 0;
  cp1n = 0;
  cp2p = 0;
  cp2n = 0;
  res = 1;
  clk = 1;
end

initial forever begin :ckgen
  #0.125 clk = ~clk;
end

initial forever begin :cpgen
  @(posedge clk) cp2n <= 0; cp1p <= 1;
  @(posedge clk) cp1p <= 0; cp1n <= 1;
  @(posedge clk) cp1n <= 0; cp2p <= 1;
  @(posedge clk) cp2p <= 0; cp2n <= 1;
end

wire cp2 = dut.cp2;

initial #0 begin
  #3 @(posedge clk) ;
  res = 0;

  // We're looping until C reaches 0 (inner loop).
  #80 @(posedge clk) ;
  dut.c = 1;

  // We're also looping until B reaches 0 (outer loop).
  #90 @(posedge clk) ;
  dut.b = 0;
  dut.c = 1;

  #800 @(posedge clk) ;

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
  $readmemh("tb/bootrom.hex", mem);
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
// compile-command: "cd .. && iverilog -g2012 -grelative-include -s bootrom_tb -o tb/bootrom_tb.vvp upd7800.sv tb/bootrom_tb.sv && tb/bootrom_tb.vvp"
// End:
