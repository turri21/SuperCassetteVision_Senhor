// Epoch TV-1 testbench: render
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

`timescale 1us / 1ps

module render_tb();

reg         clk, res;
reg [2:0]   ccnt;
reg [7:0]   din;

wire        ce;
wire [12:0] a;
wire [7:0]  dout;

initial begin
  $timeformat(-6, 0, " us", 1);

  $dumpfile("render_tb.vcd");
  $dumpvars();
end

epochtv1 dut
  (
   .CLK(clk),
   .CE(ce),
   .A(a),
   .DB_I(8'hzz),
   .DB_O(),
   .DB_OE()
   );


initial begin
  ccnt = 0;
  res = 1;
  clk = 1;
end

initial forever begin :ckgen
  #(0.25/14.318181) clk = ~clk; // 2 * 14.318181 MHz
end

always @(posedge clk)
  ccnt <= (ccnt == 3'd6) ? 0 : ccnt + 1'd1;

assign ce = (ccnt == 3'd6);

initial #0 begin
  //#11 @(posedge clk) ;

  #17000 $finish;
end


endmodule

// Local Variables:
// compile-command: "iverilog -g2012 -grelative-include -s render_tb -o render_tb.vvp ../epochtv1.sv render_tb.sv && ./render_tb.vvp"
// End:
