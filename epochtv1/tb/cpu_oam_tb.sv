// Epoch TV-1 testbench: CPU accesses OAM during render
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

`timescale 1us / 1ps

module cpu_oam_tb();

reg         clk, res;
reg [2:0]   ccnt;
reg [7:0]   din;

wire        ce;
reg [12:0]  dut_a;
reg [7:0]   dut_db_i;
wire [7:0]  dut_db_o;
reg         dut_rdb, dut_wrb, dut_csb;
wire        dut_de, ctl_de;
wire [23:0] dut_rgb, ctl_rgb;

initial begin
  $timeformat(-6, 0, " us", 1);

  $dumpfile("cpu_oam_tb.vcd");
  $dumpvars();
end

//////////////////////////////////////////////////////////////////////

vdc_vram dut
  (
   .clk(clk),
   .ce(ce),
   .a(dut_a),
   .db_i(dut_db_i),
   .db_o(dut_db_o),
   .rdb(dut_rdb),
   .wrb(dut_wrb),
   .csb(dut_csb),
   .de(dut_de),
   .rgb(dut_rgb)
   );

vdc_vram ctl
  (
   .clk(clk),
   .ce(ce),
   .a('Z),
   .db_i('Z),
   .rdb(1'b1),
   .wrb(1'b1),
   .csb(1'b1),
   .de(ctl_de),
   .rgb(ctl_rgb)
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

  code = $fread(dut.vdc.chr, fin, 0, 1024);
endtask

task load_rams(input string path);
reg [7:0] tmp [4];
integer fin, code, i;
  fin = $fopen(path, "r");
  assert(fin != 0) else $finish;

  // VRAM: $2000-$3FFF
  for (i = 0; i < 2048; i++) begin
    code = $fread(tmp, fin, 0, 2);
    dut.vrama.mem[i] = tmp[0];
    dut.vramb.mem[i] = tmp[1];
  end

  // BGM: $3000-$31FF
  code = $fread(dut.vdc.bgm, fin, 0, 512);

  // OAM: $3200-$33FF
  for (i = 0; i < 128; i++) begin
    code = $fread(tmp, fin, 0, 4);
    dut.vdc.oam[i] = {tmp[3], tmp[2], tmp[1], tmp[0]};
  end

  code = $fread(tmp, fin, 0, 4);
  //dut.vdc.reg0 = tmp[0];
  
endtask

task copy_to_ctl;
int i;
  for (i = 0; i < 2048; i++)
    ctl.vdc.chr[i] = dut.vdc.chr[i];
  for (i = 0; i < 2048; i++) begin
    ctl.vrama.mem[i] = dut.vrama.mem[i];
    ctl.vramb.mem[i] = dut.vramb.mem[i];
  end
  for (i = 0; i < 512; i++)
    ctl.vdc.bgm[i] = dut.vdc.bgm[i];
  for (i = 0; i < 128; i++)
    ctl.vdc.oam[i] = dut.vdc.oam[i];
endtask


//////////////////////////////////////////////////////////////////////

task cpu_rd(input [12:0] a, output [7:0] d);
  while (~ce) @(posedge clk) ;
  dut_a = a;
  dut_csb = 1'b0;
  repeat (14) @(posedge clk) ;
  dut_rdb = 1'b0;
  repeat (26) @(posedge clk) ;
  d = dut_db_o;
  dut_rdb = 1'b1;
  repeat (2) @(posedge clk) ;
  dut_csb = 1'b1;
endtask

task cpu_wr(input [12:0] a, input [7:0] d);
  while (~ce) @(posedge clk) ;
  dut_a = a;
  dut_csb = 1'b0;
  repeat (14) @(posedge clk) ;
  dut_wrb = 1'b0;
  dut_db_i = d;
  repeat (26) @(posedge clk) ;
  dut_wrb = 1'b1;
  //dut_db_i = 'Z;
  repeat (2) @(posedge clk) ;
  dut_csb = 1'b1;
endtask

initial #0 begin
reg [7:0] tmp;
reg [8:0] aoff;
  load_chr("epochtv.chr");
  load_rams("vram.bin");
  copy_to_ctl();

  dut_a = 0;
  dut_db_i = 'Z;
  dut_rdb = 1'b1;
  dut_wrb = 1'b1;
  dut_csb = 1'b1;

  aoff = 0;

  forever begin
    #10 cpu_rd('h1200 + aoff, tmp);
    #10 cpu_wr('h1200 + aoff, tmp);
    aoff += 1;
  end
end

initial #17000 $finish;

always @(posedge clk) if (dut_de) begin
  assert(dut_rgb === ctl_rgb);
  else begin
    $fatal(1, "output mismatch");
  end
end

endmodule

//////////////////////////////////////////////////////////////////////

module vdc_vram
  (
   input         clk,
   input         ce,

   input [12:0]  a,
   input [7:0]   db_i,
   output [7:0]  db_o,
   input         rdb,
   input         wrb,
   input         csb,

   output        de,
   output        hs,
   output        vs,
   output [23:0] rgb
   );

wire [11:0] vaa, vba;
wire [7:0]  vad_i, vad_o, vbd_i, vbd_o;
wire        nvard, nvawr, nvbrd, nvbwr;

epochtv1 vdc
  (
   .CLK(clk),
   .CE(ce),

   .A(a),
   .DB_I(db_i),
   .DB_O(db_o),
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
   .VS(vs),
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

endmodule

// Local Variables:
// compile-command: "iverilog -g2012 -grelative-include -s cpu_oam_tb -o cpu_oam_tb.vvp ../epochtv1.sv ../dpram.sv cpu_oam_tb.sv && ./cpu_oam_tb.vvp"
// End:
