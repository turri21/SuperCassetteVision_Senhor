// NEC uPD7800 testbench: timer
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

`timescale 1us / 1ps

module timer_tb();

reg         clk, res;
reg         cp1p, cp1n, cp2p, cp2n;
reg [7:0]   din;
reg [7:0]   dut_db_i;
reg         vbl;

wire [15:0] a;
wire [7:0]  dut_db_o, rom_db, wram_db;
wire        dut_rdb, dut_wrb;
wire        rom_ncs, wram_ncs, cart_ncs;

initial begin
  $timeformat(-6, 0, " us", 1);

`ifndef VERILATOR
  $dumpfile("timer_tb.vcd");
  $dumpvars();
`else
  $dumpfile("timer_tb.verilator.vcd");
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

always_comb begin
  dut_db_i = 8'hxx;
  if (~rom_ncs)
    dut_db_i = rom_db;
  else if (~wram_ncs)
    dut_db_i = wram_db;
  else if (~cart_ncs)
    dut_db_i = 8'hFF;           // cart is absent
end

assign rom_ncs = |a[15:12];
assign wram_ncs = ~&a[15:7];    // 'hFF80-'hFFFF
assign cart_ncs = ~a[15] | ~wram_ncs;


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
  #(1.0/16) clk = ~clk;
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

wire intft = dut.intp[dut.II_INTT];

initial #0 begin
  #3 @(posedge clk) ;

  // Reset conditions
  assert(dut.tc[14:3] == 12'hfff);
  assert(dut.tc[2:0] == 3'd7);
  assert(intft == 1'b0);

  res = 0;
  @(negedge dut.resg) ;         // timer starts
  @(posedge cp2) ;              // avoid timer transitions

  assert(dut.tc[14:3] == 12'hfff && dut.tc[2:0] == 3'd7);

  // Prescaler tick
  #0.5 ;
  assert(dut.tc[14:3] == 12'hfff && dut.tc[2:0] == 3'd6);

  // Counter ticks every 4us
  #(4 - 0.5) ;
  assert(dut.tc[14:3] == 12'hffe && dut.tc[2:0] == 3'd7);

  // Skip to timer underflow
  #4 dut.tc[14:3] = 12'd0;

  // Confirm timer underflow resets prescaler and counter
  assert(dut.tc[14:3] == 0 && dut.tc[2:0] == 3'd7);
  #(0.5 * 7) ;
  assert(dut.tc[14:3] == 0 && dut.tc[2:0] == 3'd0);
  assert(dut.tc_uf == 1'b0);
  @(posedge cp2n) @(negedge clk) ;
  assert(dut.tc[14:3] == 0 && dut.tc[2:0] == 3'd0);
  assert(dut.tc_uf == 1'b1);
  @(negedge clk) ;
  assert(dut.tc[14:3] == 12'hfff && dut.tc[2:0] == 3'd7);
  assert(dut.tc_uf == 1'b0);

  // INTFT set on underflow
  assert(intft == 1'b1);

  // Wait for 'SKIT INTFT' inst. to clear INTFT and set SKip flag
  @(negedge intft) ;
  @(posedge cp2) ;              // avoid timer transitions
  assert(dut.psw[5] == 1'b1);   // SKip flag

  // Confirm 'STM' inst. resets prescaler and counter
  @(dut.cl_stm) ;
  #0.5 @(posedge cp2) ;         // tick
  assert(dut.tc[14:3] == 12'h0f9 && dut.tc[2:0] == 3'd7);

  #10 $finish;
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
  $readmemh("timer.hex", mem);
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
// compile-command: "iverilog -g2012 -grelative-include -s timer_tb -o timer_tb.vvp ../upd7800.sv timer_tb.sv && ./timer_tb.vvp"
// End:
