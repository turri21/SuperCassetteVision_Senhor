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
wire        de, hs;
wire [23:0] rgb;

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
   .DB_OE(),
   .DE(de),
   .HS(hs),
   .VS(),
   .RGB(rgb)
   );

//////////////////////////////////////////////////////////////////////

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

//////////////////////////////////////////////////////////////////////

task load_chr(input string path);
integer fin, code;
  fin = $fopen(path, "r");
  assert(fin != 0) else $finish;

  code = $fread(dut.chr, fin, 0, 1024);
endtask

task load_rams(input string path);
reg [7:0] tmp [4];
integer fin, code, i;
  fin = $fopen(path, "r");
  assert(fin != 0) else $finish;

  // VRAM: $2000-$3FFF
  for (i = 0; i < 2048; i++) begin
    code = $fread(tmp, fin, 0, 2);
    dut.vram[i] = {tmp[1], tmp[0]};
  end

  // BGM: $3000-$31FF
  code = $fread(dut.bgm, fin, 0, 512);

  // OAM: $3200-$33FF
  for (i = 0; i < 128; i++) begin
    code = $fread(tmp, fin, 0, 4);
    dut.oam[i] = {tmp[3], tmp[2], tmp[1], tmp[0]};
  end

  code = $fread(tmp, fin, 0, 4);
  //dut.reg0 = tmp[0];
  
endtask

//////////////////////////////////////////////////////////////////////

integer fpic, pice;
initial begin
  fpic = $fopen("render.hex", "w");
  pice = 0;
end
always @(posedge clk) begin
  if (ce) begin
    if (de) begin
      $fwrite(fpic, "%x", rgb);
      pice = 1;
    end
    else if (pice) begin
      pice = 0;
      $fwrite(fpic, "\n");
    end
  end
end
final
  $fclose(fpic);

//////////////////////////////////////////////////////////////////////

initial #0 begin
  load_chr("epochtv.chr");
  load_rams("vram.bin");

  #17000 $finish;
end

endmodule

// Local Variables:
// compile-command: "iverilog -g2012 -grelative-include -s render_tb -o render_tb.vvp ../epochtv1.sv render_tb.sv && ./render_tb.vvp && make render.png"
// End:
