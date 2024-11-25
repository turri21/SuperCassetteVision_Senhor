// NEC uPD1771C testbench: play a digital packet
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

`timescale 1us / 1ps

module digital_tb();

reg         clk, res;
wire [7:0]  pa_i, pb_i, pb_o;
logic [7:0] din;
logic       ncs, nwr;
wire        dsb;
int         cycle;
wire [8:0]  pcm_out;

initial begin
  $timeformat(-6, 0, " us", 1);

  $dumpfile("digital_tb.vcd");
  //$dumpvars();
end

upd1771c dut
  (
   .CLK(clk),
   .CKEN('1),
   .RESB(~res),
   .CH1('1),
   .CH2('0),
   .PA_I(pa_i),
   .PA_OE(),
   .PA_O(),
   .PB_I(pb_i),
   .PB_O(pb_o),
   .PB_OE(),
   .PCM_OUT(pcm_out)
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
  repeat (8*9)
    @(posedge clk) ;
endtask

task packet_start(input [7:0] b);
  // Align to CP1
  while (~dut.cp1p)
    @(posedge clk) ;
  tx(b);
endtask

task packet_cont(input [7:0] b);
  while (~dsb)
    repeat (80)
      @(posedge clk) ;
  tx(b);
  while (dsb)
    repeat (80)
      @(posedge clk) ;
endtask

always begin :ckgen
  #(0.5/6) clk = ~clk;
end

always @(posedge clk) begin
  if (~res & dut.cp1p)
    cycle += 1;
end

//////////////////////////////////////////////////////////////////////

// To play the file:
//   play -b 16 -r 750000 -c 1 -B -e signed-integer dig.raw

integer faud;
wire [15:0] aud_out = {pcm_out, 7'b0};
initial begin
  faud = $fopen("dig.raw", "w");
end
always @(posedge clk) begin
  if (~res & dut.cp1p) begin
    $fwrite(faud, "%c%c", aud_out[15:8], aud_out[7:0]);
  end
end
final
  $fclose(faud);

//////////////////////////////////////////////////////////////////////

logic [7:0] dig [1128];
initial
  $readmemh("dig.hex", dig);

initial #0 begin
  res = 1;
  clk = 1;
  din = 8'hxx;
  ncs = 1;
  nwr = 1;
  cycle = 0;

  #2 @(posedge clk) ;
  res = 0;

  #318 @(posedge clk) ;

  packet_start(8'h1f);
  for (int i = 0; i < 1128; i++)
    packet_cont(dig[i]);

  $finish;
end

wire [7:0] r01 = dut.ram_right_mem[0][0];
wire [7:0] r04 = dut.ram_left_mem[0][2];

endmodule


// Local Variables:
// compile-command: "iverilog -g2012 -grelative-include -DUPD1771C_ROM_INIT_FROM_HEX -s digital_tb -o digital_tb.vvp ../upd1771c.sv digital_tb.sv && ./digital_tb.vvp"
// End:
