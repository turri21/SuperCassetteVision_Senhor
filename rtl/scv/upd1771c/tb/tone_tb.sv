// NEC uPD1771C testbench: play the tone warble heard on PAUSE
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

`timescale 1us / 1ps

module tone_tb();

reg         clk, res;
wire [7:0]  pa_i, pb_i, pb_o;
logic [7:0] din;
logic       ncs, nwr;
wire        dsb;

initial begin
  $timeformat(-6, 0, " us", 1);

  $dumpfile("tone_tb.vcd");
  $dumpvars();
end

upd1771c dut
  (
   .CLK(clk),
   .RESB(~res),
   .CH1('1),
   .CH2('0),
   .PA_I(pa_i),
   .PA_OE(),
   .PA_O(),
   .PB_I(pb_i),
   .PB_O(pb_o),
   .PB_OE()
   );

assign pa_i = din;
assign pb_i[7] = ncs;
assign pb_i[6] = nwr;
assign pb_i[5:0] = '1;

assign dsb = pb_o[0];

task tx(input [7:0] b);
  if (~clk)
    @(posedge clk) ;
  din <= b;
  ncs <= 0;
  nwr <= 0;
  repeat (8)
    @(posedge clk) ;
  ncs <= 1;
  nwr <= 1;
endtask

task packet_start(input [7:0] b);
  tx(b);
endtask

task packet_cont(input [7:0] b);
  while (~dsb)
    repeat (8)
      @(posedge clk) ;
  tx(b);
  while (dsb)
    repeat (8)
      @(posedge clk) ;
endtask

always begin :ckgen
  #(0.5/6) clk = ~clk;
end

initial #0 begin
  res = 1;
  clk = 1;
  din = 8'hxx;
  ncs = 1;
  nwr = 1;

  #2 @(posedge clk) ;
  res = 0;

  #320 @(posedge clk) ;

  packet_start(8'h02);
  packet_cont(8'h80);
  packet_cont(8'h35);
  packet_cont(8'h15);

  #10000 @(posedge clk) ;

  packet_start(8'h02);
  packet_cont(8'h80);
  packet_cont(8'h4f);
  packet_cont(8'h15);

  #10000 @(posedge clk) ;

  $finish;
end

initial #30000
  $finish;

endmodule


// Local Variables:
// compile-command: "iverilog -g2012 -grelative-include -s tone_tb -o tone_tb.vvp ../upd1771c.sv tone_tb.sv && ./tone_tb.vvp"
// End:
