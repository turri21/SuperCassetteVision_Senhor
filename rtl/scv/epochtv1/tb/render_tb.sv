// Epoch TV-1 testbench: render
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

// From MAME debugger: save vram.bin,2000,1404

`timescale 1us / 1ps

module render_tb();

reg         clk, res;
reg [2:0]   ccnt;
reg [12:0]  a;
reg [7:0]   din;
reg         rdb, wrb, csb;
reg [7:0]   ioreg [4];

wire        ce;
wire [7:0]  dout;
wire [11:0] vaa, vba;
wire [7:0]  vad_i, vad_o, vbd_i, vbd_o;
wire        nvard, nvawr, nvbrd, nvbwr;
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
   .DB_I(din),
   .DB_O(dout),
   .DB_OE(),
   .RDB(rdb),
   .WRB(wrb),
   .CSB(csb),

   .VAA(vaa),
   .VAD_I(vad_i),
   .VAD_O(vad_o),
   .nVARD(nvard),
   .nVAWR(nvawr),

   .VBA(vba),
   .VBD_I(vbd_i),
   .VBD_O(vbd_o),
   .nVBRD(nvbrd),
   .nVBWR(nvbwr),

   .DE(de),
   .HS(hs),
   .VS(),
   .RGB(rgb)
   );

dpram #(.DWIDTH(8), .AWIDTH(12)) vrama
  (
   .CLK(clk),

   .nCE(nvard & nvawr),
   .nWE(nvawr),
   .nOE(nvard),
   .A(vaa),
   .DI(vad_o),
   .DO(vad_i),

   .nCE2(1'b1),
   .nWE2(1'b1),
   .nOE2(1'b1),
   .A2(),
   .DI2(),
   .DO2()
   );

dpram #(.DWIDTH(8), .AWIDTH(12)) vramb
  (
   .CLK(clk),

   .nCE(nvbrd & nvbwr),
   .nWE(nvbwr),
   .nOE(nvbrd),
   .A(vba),
   .DI(vbd_o),
   .DO(vbd_i),

   .nCE2(1'b1),
   .nWE2(1'b1),
   .nOE2(1'b1),
   .A2(),
   .DI2(),
   .DO2()
   );

//////////////////////////////////////////////////////////////////////

initial begin
  ccnt = 0;
  res = 1;
  clk = 1;

  rdb = 1;
  wrb = 1;
  csb = 1;
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
  assert(fin != 0) else $fatal(1, "missing CHR ROM %s", path);

  code = $fread(dut.chr, fin, 0, 1024);
endtask

task load_rams(input string path);
reg [7:0] tmp [4];
integer fin, code, i;
  fin = $fopen(path, "r");
  assert(fin != 0) else $fatal(1, "missing RAM %s", path);

  // VRAM: $2000-$3FFF
  for (i = 0; i < 2048; i++) begin
    code = $fread(tmp, fin, 0, 2);
    vrama.mem[i] = tmp[0];
    vramb.mem[i] = tmp[1];
  end

  // BGM: $3000-$31FF
  for (i = 0; i < 128; i++) begin
    code = $fread(tmp, fin, 0, 4);
    dut.bgm[i] = {tmp[3], tmp[2], tmp[1], tmp[0]};
  end

  // OAM: $3200-$33FF
  for (i = 0; i < 128; i++) begin
    code = $fread(tmp, fin, 0, 4);
    dut.oam[i] = {tmp[3], tmp[2], tmp[1], tmp[0]};
  end

  code = $fread(tmp, fin, 0, 4);
  ioreg[0] = tmp[0];
  ioreg[1] = tmp[1];
  ioreg[2] = tmp[2];
  ioreg[3] = tmp[3];

endtask

//////////////////////////////////////////////////////////////////////

task ioreg_write(input [1:0] rs, input [7:0] v);
  while (!ce)
    @(posedge clk) ;
  a <= {11'h500, rs};
  din <= v;
  wrb <= 0;
  csb <= 0;

  @(posedge clk) ;
  while (!ce)
    @(posedge clk) ;
  wrb <= 1;
  csb <= 1;
  
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

event init_regs;

always @(init_regs) begin
  ioreg_write(0, ioreg[0]);
  ioreg_write(1, ioreg[1]);
  ioreg_write(2, ioreg[2]);
  ioreg_write(3, ioreg[3]);
end

initial #0 begin
  dut.row = dut.FIRST_ROW_BOC_START - 1;

  load_chr("epochtv.chr");
  load_rams("doraemon-game-vram.bin");

  -> init_regs;

  #17500 $finish;
end

endmodule

// Local Variables:
// compile-command: "iverilog -g2012 -grelative-include -s render_tb -o render_tb.vvp ../epochtv1.sv ../dpram.sv render_tb.sv && ./render_tb.vvp && make render.png"
// End:
