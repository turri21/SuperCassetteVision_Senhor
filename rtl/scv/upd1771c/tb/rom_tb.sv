// NEC uPD1771C testbench: use testmode to dump ROM
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

`timescale 1us / 1ps

module rom_tb();

reg         clk, res;

initial begin
  $timeformat(-6, 0, " us", 1);

  $dumpfile("rom_tb.vcd");
  $dumpvars();
end

upd1771c dut
  (
   .CLK(clk),
   .RESB(~res),
   .CH1('X),
   .CH2('1),
   .PA_I(8'hxx),
   .PA_OE(),
   .PA_O(),
   .PB_I(8'hxx),
   .PB_O(),
   .PB_OE()
   );


initial begin
  res = 1;
  clk = 1;
end

always begin :ckgen
  #(0.5/6) clk = ~clk;
end

initial #0 begin

  #2 @(posedge clk) ;
  res = 0;

  #(10e3) @(posedge clk) ;

  $finish;
end

endmodule


// Local Variables:
// compile-command: "iverilog -g2012 -grelative-include -s rom_tb -o rom_tb.vvp ../upd1771c.sv rom_tb.sv && ./rom_tb.vvp"
// End:
