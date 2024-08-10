`timescale 1us / 1ns

module dpram
  #(parameter DWIDTH=8, 
    parameter AWIDTH=16)
  (
   input               CLK,

   input               nCE,
   input               nWE,
   input               nOE,
   input [AWIDTH-1:0]  A,
   input [DWIDTH-1:0]  DI,
   output [DWIDTH-1:0] DO,

   input               nCE2,
   input               nWE2,
   input               nOE2,
   input [AWIDTH-1:0]  A2,
   input [DWIDTH-1:0]  DI2,
   output [DWIDTH-1:0] DO2
   );

reg [DWIDTH-1:0] mem [0:(1<<AWIDTH)-1];
reg [DWIDTH-1:0] d, d2;

always @(posedge CLK) begin
  if (~(nCE | nOE)) begin
    d <= mem[A];
  end

  if (~(nCE | nWE)) begin
    mem[A] <= DI;
  end
end

always @(posedge CLK) begin
  if (~(nCE2 | nOE2)) begin
    d2 <= mem[A2];
  end

  if (~(nCE2 | nWE2)) begin
    mem[A2] <= DI2;
  end
end

assign DO = d;
assign DO2 = d2;

endmodule
