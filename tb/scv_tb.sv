// Super Cassette Vision testbench: boot with no cart
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

`timescale 1us / 1ps

// Get to the main loop faster, by shorting loops.
`ifndef VERILATOR
`define FAST_MAIN 1
`endif

module scv_tb();

reg         clk, res;

initial begin
  $timeformat(-6, 0, " us", 1);

`ifndef VERILATOR
  $dumpfile("scv_tb.vcd");
  $dumpvars();
`else
  $dumpfile("scv_tb.verilator.vcd");
  $dumpvars();
`endif
end

scv dut
  (
   .CLK(clk),
   .RESB(~res)
   );

initial begin
  res = 1;
  clk = 1;
end

initial forever begin :ckgen
  #(0.25/14.318181) clk = ~clk; // 2 * 14.318181 MHz
end

initial #0 begin
  #2 @(posedge clk) ;
  res = 0;

`ifdef FAST_MAIN
  // We're looping until C reaches 0 (inner loop).
  #40 @(posedge clk) ;
  assert(dut.cpu.pc == 16'h0016);
  dut.cpu.c = 1;

  // We're also looping until B reaches 0 (outer loop).
  #43 @(posedge clk) ;
  assert(dut.cpu.pc == 16'h0018);
  dut.cpu.b = 0;
  dut.cpu.c = 1;
  #1 ;
`endif

`ifndef VERILATOR
  #(60e3) @(posedge clk) ;
`else
  #(500e3) @(posedge clk) ;
`endif

  $finish;
end

endmodule


// Local Variables:
// compile-command: "iverilog -g2012 -grelative-include -s scv_tb -o scv_tb.vvp ../scv.sv ../upd7800/upd7800.sv ../epochtv1/epochtv1.sv ../epochtv1/dpram.sv scv_tb.sv && ./scv_tb.vvp"
// End:
