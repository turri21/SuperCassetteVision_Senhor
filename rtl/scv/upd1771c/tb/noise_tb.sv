// NEC uPD1771C testbench: play the engine rev heard at Wheelie Racer boot
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

`timescale 1us / 1ps

/* verilator lint_off INITIALDLY */

module noise_tb();

reg         clk, res;
wire [7:0]  pa_i, pb_i, pb_o;
logic [7:0] din;
logic       ncs, nwr;
wire        dsb;
int         cycle;
wire [8:0]  pcm_out;

initial begin
  $timeformat(-6, 0, " us", 1);

  $dumpfile("noise_tb.vcd");
  $dumpvars();
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
  // Align to PHI2
  while (~dut.phi2p)
    @(posedge clk) ;
  tx(b);
endtask

task packet_cont(input [7:0] b);
  while (~dsb)
    repeat (40)
      @(posedge clk) ;
  tx(b);
  while (dsb)
    repeat (40)
      @(posedge clk) ;
endtask

always begin :ckgen
  #(0.5/6) clk = ~clk;
end

always @(posedge clk) begin
  if (~res & dut.phi2p)
    cycle += 1;
end

//////////////////////////////////////////////////////////////////////

// To play the file:
//   play -b 16 -r 750000 -c 1 -B -e signed-integer noise.raw

integer faud;
wire [15:0] aud_out = {pcm_out, 7'b0};
initial begin
  faud = $fopen("noise.raw", "w");
end
always @(posedge clk) begin
  if (~res & dut.phi2p) begin
    $fwrite(faud, "%c%c", aud_out[15:8], aud_out[7:0]);
  end
end
final
  $fclose(faud);

//////////////////////////////////////////////////////////////////////

logic [7:0] packets [257][9];

task init_pkt(int idx,
              input [7:0] b1, input [7:0] b2, input [7:0] b3,
              input [7:0] b4, input [7:0] b5, input [7:0] b6,
              input [7:0] b7, input [7:0] b8, input [7:0] b9);
  packets[idx][0] = b1;
  packets[idx][1] = b2;
  packets[idx][2] = b3;
  packets[idx][3] = b4;
  packets[idx][4] = b5;
  packets[idx][5] = b6;
  packets[idx][6] = b7;
  packets[idx][7] = b8;
  packets[idx][8] = b9;
endtask

task init_packets;
  init_pkt(  0, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00);
  init_pkt(  1, 8'h00, 8'h48, 8'h00, 8'h48, 8'h00, 8'h48, 8'h00, 8'h00, 8'h00);
  init_pkt(  2, 8'h00, 8'h24, 8'h00, 8'h24, 8'h00, 8'h24, 8'h00, 8'h00, 8'h00);
  init_pkt(  3, 8'h00, 8'hff, 8'h00, 8'hff, 8'h00, 8'hff, 8'h00, 8'h00, 8'h00);
  init_pkt(  4, 8'h00, 8'hff, 8'h00, 8'hff, 8'h00, 8'hff, 8'h00, 8'h00, 8'h00);
  init_pkt(  5, 8'h00, 8'hff, 8'h00, 8'hff, 8'h00, 8'hff, 8'h00, 8'h00, 8'h00);
  init_pkt(  6, 8'h00, 8'hff, 8'h00, 8'hff, 8'h00, 8'hff, 8'h00, 8'h00, 8'h00);
  init_pkt(  7, 8'h00, 8'hff, 8'h00, 8'hff, 8'h00, 8'hff, 8'h00, 8'h00, 8'h00);
  init_pkt(  8, 8'h00, 8'hff, 8'h00, 8'hff, 8'h20, 8'h40, 8'h00, 8'h30, 8'h50);
  init_pkt(  9, 8'h00, 8'h45, 8'h00, 8'h45, 8'h1f, 8'h3e, 8'h00, 8'h10, 8'h28);
  init_pkt( 10, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1d, 8'h3c, 8'h00, 8'h30, 8'h50);
  init_pkt( 11, 8'h00, 8'h18, 8'h00, 8'h18, 8'h1e, 8'h3a, 8'h00, 8'h10, 8'h28);
  init_pkt( 12, 8'h00, 8'h0c, 8'h00, 8'h0c, 8'h1c, 8'h38, 8'h00, 8'h30, 8'h50);
  init_pkt( 13, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1b, 8'h36, 8'h00, 8'h10, 8'h28);
  init_pkt( 14, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1a, 8'h34, 8'h00, 8'h30, 8'h50);
  init_pkt( 15, 8'h00, 8'h00, 8'h00, 8'h00, 8'h20, 8'h32, 8'h00, 8'h10, 8'h28);
  init_pkt( 16, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1f, 8'h30, 8'h00, 8'h30, 8'h50);
  init_pkt( 17, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1d, 8'h2e, 8'h00, 8'h10, 8'h28);
  init_pkt( 18, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1e, 8'h2c, 8'h00, 8'h30, 8'h50);
  init_pkt( 19, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1c, 8'h2a, 8'h00, 8'h10, 8'h28);
  init_pkt( 20, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1b, 8'h28, 8'h00, 8'h30, 8'h50);
  init_pkt( 21, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1a, 8'h26, 8'h00, 8'h10, 8'h28);
  init_pkt( 22, 8'h00, 8'h00, 8'h00, 8'h00, 8'h20, 8'h24, 8'h00, 8'h30, 8'h50);
  init_pkt( 23, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1f, 8'h22, 8'h00, 8'h10, 8'h28);
  init_pkt( 24, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1d, 8'h20, 8'h00, 8'h30, 8'h50);
  init_pkt( 25, 8'h00, 8'h64, 8'h00, 8'h64, 8'h1e, 8'h22, 8'h00, 8'h10, 8'h28);
  init_pkt( 26, 8'h00, 8'h4c, 8'h00, 8'h4c, 8'h1c, 8'h24, 8'h00, 8'h30, 8'h50);
  init_pkt( 27, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1b, 8'h26, 8'h00, 8'h10, 8'h28);
  init_pkt( 28, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1a, 8'h28, 8'h00, 8'h30, 8'h50);
  init_pkt( 29, 8'h00, 8'h1b, 8'h00, 8'h1b, 8'h20, 8'h2a, 8'h00, 8'h10, 8'h28);
  init_pkt( 30, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1f, 8'h2c, 8'h00, 8'h30, 8'h50);
  init_pkt( 31, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1d, 8'h2e, 8'h00, 8'h10, 8'h28);
  init_pkt( 32, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1e, 8'h30, 8'h00, 8'h30, 8'h50);
  init_pkt( 33, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1c, 8'h32, 8'h00, 8'h10, 8'h28);
  init_pkt( 34, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1b, 8'h34, 8'h00, 8'h30, 8'h50);
  init_pkt( 35, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1a, 8'h36, 8'h00, 8'h10, 8'h28);
  init_pkt( 36, 8'h00, 8'h00, 8'h00, 8'h00, 8'h20, 8'h38, 8'h00, 8'h30, 8'h50);
  init_pkt( 37, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1f, 8'h3a, 8'h00, 8'h10, 8'h28);
  init_pkt( 38, 8'h00, 8'h4e, 8'h00, 8'h4e, 8'h1d, 8'h3c, 8'h00, 8'h30, 8'h50);
  init_pkt( 39, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1e, 8'h3e, 8'h00, 8'h10, 8'h28);
  init_pkt( 40, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1c, 8'h40, 8'h00, 8'h30, 8'h50);
  init_pkt( 41, 8'h00, 8'h01, 8'h00, 8'h01, 8'h1b, 8'h3e, 8'h00, 8'h10, 8'h28);
  init_pkt( 42, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1a, 8'h3c, 8'h00, 8'h30, 8'h50);
  init_pkt( 43, 8'h00, 8'h00, 8'h00, 8'h00, 8'h20, 8'h3a, 8'h00, 8'h10, 8'h28);
  init_pkt( 44, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1f, 8'h38, 8'h00, 8'h30, 8'h50);
  init_pkt( 45, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1d, 8'h36, 8'h00, 8'h10, 8'h28);
  init_pkt( 46, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1e, 8'h34, 8'h00, 8'h30, 8'h50);
  init_pkt( 47, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1c, 8'h32, 8'h00, 8'h10, 8'h28);
  init_pkt( 48, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1b, 8'h30, 8'h00, 8'h30, 8'h50);
  init_pkt( 49, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1a, 8'h2e, 8'h00, 8'h10, 8'h28);
  init_pkt( 50, 8'h00, 8'hff, 8'h00, 8'hff, 8'h20, 8'h2c, 8'h00, 8'h30, 8'h50);
  init_pkt( 51, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1f, 8'h2a, 8'h00, 8'h10, 8'h28);
  init_pkt( 52, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1d, 8'h28, 8'h00, 8'h30, 8'h50);
  init_pkt( 53, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1e, 8'h26, 8'h00, 8'h10, 8'h28);
  init_pkt( 54, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1c, 8'h24, 8'h00, 8'h30, 8'h50);
  init_pkt( 55, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1b, 8'h22, 8'h00, 8'h10, 8'h28);
  init_pkt( 56, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1a, 8'h20, 8'h00, 8'h30, 8'h50);
  init_pkt( 57, 8'h00, 8'hff, 8'h00, 8'hff, 8'h20, 8'h22, 8'h00, 8'h10, 8'h28);
  init_pkt( 58, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1f, 8'h24, 8'h00, 8'h30, 8'h50);
  init_pkt( 59, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1d, 8'h26, 8'h00, 8'h10, 8'h28);
  init_pkt( 60, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1e, 8'h28, 8'h00, 8'h30, 8'h50);
  init_pkt( 61, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1c, 8'h2a, 8'h00, 8'h10, 8'h28);
  init_pkt( 62, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1b, 8'h2c, 8'h00, 8'h30, 8'h50);
  init_pkt( 63, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1a, 8'h2e, 8'h00, 8'h10, 8'h28);
  init_pkt( 64, 8'h00, 8'hff, 8'h00, 8'hff, 8'h20, 8'h30, 8'h00, 8'h30, 8'h50);
  init_pkt( 65, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1f, 8'h32, 8'h00, 8'h10, 8'h28);
  init_pkt( 66, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1d, 8'h34, 8'h00, 8'h30, 8'h50);
  init_pkt( 67, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1e, 8'h36, 8'h00, 8'h10, 8'h28);
  init_pkt( 68, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1c, 8'h38, 8'h00, 8'h30, 8'h50);
  init_pkt( 69, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1b, 8'h3a, 8'h00, 8'h10, 8'h28);
  init_pkt( 70, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1a, 8'h3c, 8'h00, 8'h30, 8'h50);
  init_pkt( 71, 8'h00, 8'hff, 8'h00, 8'hff, 8'h20, 8'h3e, 8'h00, 8'h10, 8'h28);
  init_pkt( 72, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1f, 8'h40, 8'h00, 8'h30, 8'h50);
  init_pkt( 73, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1d, 8'h3e, 8'h00, 8'h10, 8'h28);
  init_pkt( 74, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1e, 8'h3c, 8'h00, 8'h30, 8'h50);
  init_pkt( 75, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1c, 8'h3a, 8'h00, 8'h10, 8'h28);
  init_pkt( 76, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1b, 8'h38, 8'h00, 8'h30, 8'h50);
  init_pkt( 77, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1a, 8'h36, 8'h00, 8'h10, 8'h28);
  init_pkt( 78, 8'h00, 8'h00, 8'h00, 8'h00, 8'h20, 8'h34, 8'h00, 8'h30, 8'h50);
  init_pkt( 79, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1f, 8'h32, 8'h00, 8'h10, 8'h28);
  init_pkt( 80, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1d, 8'h30, 8'h00, 8'h30, 8'h50);
  init_pkt( 81, 8'h00, 8'h60, 8'h00, 8'h60, 8'h1e, 8'h2e, 8'h00, 8'h10, 8'h28);
  init_pkt( 82, 8'h00, 8'h0d, 8'h00, 8'h0d, 8'h1c, 8'h2c, 8'h00, 8'h30, 8'h50);
  init_pkt( 83, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1b, 8'h2a, 8'h00, 8'h10, 8'h28);
  init_pkt( 84, 8'h00, 8'h10, 8'h00, 8'h10, 8'h1a, 8'h28, 8'h00, 8'h30, 8'h50);
  init_pkt( 85, 8'h00, 8'h80, 8'h00, 8'h80, 8'h20, 8'h26, 8'h00, 8'h10, 8'h28);
  init_pkt( 86, 8'h00, 8'h01, 8'h00, 8'h01, 8'h1f, 8'h24, 8'h00, 8'h30, 8'h50);
  init_pkt( 87, 8'h00, 8'h73, 8'h00, 8'h73, 8'h1d, 8'h22, 8'h00, 8'h10, 8'h28);
  init_pkt( 88, 8'h00, 8'h37, 8'h00, 8'h37, 8'h1e, 8'h20, 8'h00, 8'h30, 8'h50);
  init_pkt( 89, 8'h00, 8'h29, 8'h00, 8'h29, 8'h1c, 8'h22, 8'h00, 8'h10, 8'h28);
  init_pkt( 90, 8'h00, 8'h76, 8'h00, 8'h76, 8'h1b, 8'h24, 8'h00, 8'h30, 8'h50);
  init_pkt( 91, 8'h00, 8'h06, 8'h00, 8'h06, 8'h1a, 8'h26, 8'h00, 8'h10, 8'h28);
  init_pkt( 92, 8'h00, 8'h00, 8'h00, 8'h00, 8'h20, 8'h28, 8'h00, 8'h30, 8'h50);
  init_pkt( 93, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1f, 8'h2a, 8'h00, 8'h10, 8'h28);
  init_pkt( 94, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1d, 8'h2c, 8'h00, 8'h30, 8'h50);
  init_pkt( 95, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1e, 8'h2e, 8'h00, 8'h10, 8'h28);
  init_pkt( 96, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1c, 8'h30, 8'h00, 8'h30, 8'h50);
  init_pkt( 97, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1b, 8'h32, 8'h00, 8'h10, 8'h28);
  init_pkt( 98, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1a, 8'h34, 8'h00, 8'h30, 8'h50);
  init_pkt( 99, 8'h00, 8'h00, 8'h00, 8'h00, 8'h20, 8'h36, 8'h00, 8'h10, 8'h28);
  init_pkt(100, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1f, 8'h38, 8'h00, 8'h30, 8'h50);
  init_pkt(101, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1d, 8'h3a, 8'h00, 8'h10, 8'h28);
  init_pkt(102, 8'h00, 8'h21, 8'h00, 8'h21, 8'h1e, 8'h3c, 8'h00, 8'h30, 8'h50);
  init_pkt(103, 8'h00, 8'h01, 8'h00, 8'h01, 8'h1c, 8'h3e, 8'h00, 8'h10, 8'h28);
  init_pkt(104, 8'h00, 8'h08, 8'h00, 8'h08, 8'h1b, 8'h40, 8'h00, 8'h30, 8'h50);
  init_pkt(105, 8'h00, 8'h42, 8'h00, 8'h42, 8'h1a, 8'h40, 8'h00, 8'h10, 8'h28);
  init_pkt(106, 8'h00, 8'hff, 8'h00, 8'hff, 8'h20, 8'h40, 8'h00, 8'h30, 8'h50);
  init_pkt(107, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1f, 8'h3f, 8'h00, 8'h10, 8'h28);
  init_pkt(108, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1d, 8'h3f, 8'h00, 8'h30, 8'h50);
  init_pkt(109, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1e, 8'h3f, 8'h00, 8'h10, 8'h28);
  init_pkt(110, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1c, 8'h3e, 8'h00, 8'h30, 8'h50);
  init_pkt(111, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1b, 8'h3e, 8'h00, 8'h10, 8'h28);
  init_pkt(112, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1a, 8'h3e, 8'h00, 8'h30, 8'h50);
  init_pkt(113, 8'h00, 8'hff, 8'h00, 8'hff, 8'h20, 8'h3d, 8'h00, 8'h10, 8'h28);
  init_pkt(114, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1f, 8'h3d, 8'h00, 8'h30, 8'h50);
  init_pkt(115, 8'h00, 8'h33, 8'h00, 8'h33, 8'h1d, 8'h3d, 8'h00, 8'h10, 8'h28);
  init_pkt(116, 8'h00, 8'h33, 8'h00, 8'h33, 8'h1e, 8'h3c, 8'h00, 8'h30, 8'h50);
  init_pkt(117, 8'h00, 8'h33, 8'h00, 8'h33, 8'h1c, 8'h3c, 8'h00, 8'h10, 8'h28);
  init_pkt(118, 8'h00, 8'h33, 8'h00, 8'h33, 8'h1b, 8'h3c, 8'h00, 8'h30, 8'h50);
  init_pkt(119, 8'h00, 8'hfe, 8'h00, 8'hfe, 8'h1a, 8'h3b, 8'h00, 8'h10, 8'h28);
  init_pkt(120, 8'h00, 8'hff, 8'h00, 8'hff, 8'h20, 8'h3b, 8'h00, 8'h30, 8'h50);
  init_pkt(121, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1f, 8'h3b, 8'h00, 8'h10, 8'h28);
  init_pkt(122, 8'h00, 8'hef, 8'h00, 8'hef, 8'h1d, 8'h3a, 8'h00, 8'h30, 8'h50);
  init_pkt(123, 8'h00, 8'hfe, 8'h00, 8'hfe, 8'h1e, 8'h3a, 8'h00, 8'h10, 8'h28);
  init_pkt(124, 8'h00, 8'hff, 8'h00, 8'hff, 8'h1c, 8'h3a, 8'h00, 8'h30, 8'h50);
  init_pkt(125, 8'h00, 8'h10, 8'h00, 8'h10, 8'h1b, 8'h39, 8'h00, 8'h10, 8'h28);
  init_pkt(126, 8'h00, 8'h11, 8'h00, 8'h11, 8'h1a, 8'h39, 8'h00, 8'h30, 8'h50);
  init_pkt(127, 8'h00, 8'h83, 8'h00, 8'h83, 8'h20, 8'h39, 8'h00, 8'h10, 8'h28);
  init_pkt(128, 8'h00, 8'h88, 8'h00, 8'h88, 8'h1f, 8'h38, 8'h00, 8'h30, 8'h50);
  init_pkt(129, 8'h00, 8'h51, 8'h00, 8'h51, 8'h1d, 8'h38, 8'h00, 8'h10, 8'h28);
  init_pkt(130, 8'h00, 8'h2b, 8'h00, 8'h2b, 8'h1e, 8'h38, 8'h00, 8'h30, 8'h50);
  init_pkt(131, 8'h00, 8'h3c, 8'h00, 8'h3c, 8'h1c, 8'h37, 8'h00, 8'h10, 8'h28);
  init_pkt(132, 8'h00, 8'hd7, 8'h00, 8'hd7, 8'h1b, 8'h37, 8'h00, 8'h30, 8'h50);
  init_pkt(133, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1a, 8'h37, 8'h00, 8'h10, 8'h28);
  init_pkt(134, 8'h00, 8'h00, 8'h00, 8'h00, 8'h20, 8'h36, 8'h00, 8'h30, 8'h50);
  init_pkt(135, 8'h00, 8'hfc, 8'h00, 8'hfc, 8'h1f, 8'h36, 8'h00, 8'h10, 8'h28);
  init_pkt(136, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1d, 8'h36, 8'h00, 8'h30, 8'h50);
  init_pkt(137, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1e, 8'h35, 8'h00, 8'h10, 8'h28);
  init_pkt(138, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1c, 8'h35, 8'h00, 8'h30, 8'h50);
  init_pkt(139, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1b, 8'h35, 8'h00, 8'h10, 8'h28);
  init_pkt(140, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1a, 8'h34, 8'h00, 8'h30, 8'h50);
  init_pkt(141, 8'h00, 8'h00, 8'h00, 8'h00, 8'h20, 8'h34, 8'h00, 8'h10, 8'h28);
  init_pkt(142, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1f, 8'h34, 8'h00, 8'h30, 8'h50);
  init_pkt(143, 8'h00, 8'h37, 8'h00, 8'h37, 8'h1d, 8'h33, 8'h00, 8'h10, 8'h28);
  init_pkt(144, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1e, 8'h33, 8'h00, 8'h30, 8'h50);
  init_pkt(145, 8'h00, 8'h20, 8'h00, 8'h20, 8'h1c, 8'h33, 8'h00, 8'h10, 8'h28);
  init_pkt(146, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1b, 8'h32, 8'h00, 8'h30, 8'h50);
  init_pkt(147, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1a, 8'h32, 8'h00, 8'h10, 8'h28);
  init_pkt(148, 8'h00, 8'h00, 8'h00, 8'h00, 8'h20, 8'h32, 8'h00, 8'h30, 8'h50);
  init_pkt(149, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1f, 8'h31, 8'h00, 8'h10, 8'h28);
  init_pkt(150, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1d, 8'h31, 8'h00, 8'h30, 8'h50);
  init_pkt(151, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1e, 8'h31, 8'h00, 8'h10, 8'h28);
  init_pkt(152, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1c, 8'h30, 8'h00, 8'h30, 8'h50);
  init_pkt(153, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1b, 8'h30, 8'h00, 8'h10, 8'h28);
  init_pkt(154, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1a, 8'h30, 8'h00, 8'h30, 8'h50);
  init_pkt(155, 8'h00, 8'h00, 8'h00, 8'h00, 8'h20, 8'h2f, 8'h00, 8'h10, 8'h28);
  init_pkt(156, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1f, 8'h2f, 8'h00, 8'h30, 8'h50);
  init_pkt(157, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1d, 8'h2f, 8'h00, 8'h10, 8'h28);
  init_pkt(158, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1e, 8'h2e, 8'h00, 8'h30, 8'h50);
  init_pkt(159, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1c, 8'h2e, 8'h00, 8'h10, 8'h28);
  init_pkt(160, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1b, 8'h2e, 8'h00, 8'h30, 8'h50);
  init_pkt(161, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1a, 8'h2d, 8'h00, 8'h10, 8'h28);
  init_pkt(162, 8'h00, 8'h00, 8'h00, 8'h00, 8'h20, 8'h2d, 8'h00, 8'h30, 8'h50);
  init_pkt(163, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1f, 8'h2d, 8'h00, 8'h10, 8'h28);
  init_pkt(164, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1d, 8'h2c, 8'h00, 8'h30, 8'h50);
  init_pkt(165, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1e, 8'h2c, 8'h00, 8'h10, 8'h28);
  init_pkt(166, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1c, 8'h2c, 8'h00, 8'h30, 8'h50);
  init_pkt(167, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1b, 8'h2b, 8'h00, 8'h10, 8'h28);
  init_pkt(168, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1a, 8'h2b, 8'h00, 8'h30, 8'h50);
  init_pkt(169, 8'h00, 8'h30, 8'h00, 8'h30, 8'h20, 8'h2b, 8'h00, 8'h10, 8'h28);
  init_pkt(170, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1f, 8'h2a, 8'h00, 8'h30, 8'h50);
  init_pkt(171, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1d, 8'h2a, 8'h00, 8'h10, 8'h28);
  init_pkt(172, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1e, 8'h2a, 8'h00, 8'h30, 8'h50);
  init_pkt(173, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1c, 8'h29, 8'h00, 8'h10, 8'h28);
  init_pkt(174, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1b, 8'h29, 8'h00, 8'h30, 8'h50);
  init_pkt(175, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1a, 8'h29, 8'h00, 8'h10, 8'h28);
  init_pkt(176, 8'h00, 8'h00, 8'h00, 8'h00, 8'h20, 8'h28, 8'h00, 8'h30, 8'h50);
  init_pkt(177, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1f, 8'h28, 8'h00, 8'h10, 8'h28);
  init_pkt(178, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1d, 8'h28, 8'h00, 8'h30, 8'h50);
  init_pkt(179, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1e, 8'h27, 8'h00, 8'h10, 8'h28);
  init_pkt(180, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1c, 8'h27, 8'h00, 8'h30, 8'h50);
  init_pkt(181, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1b, 8'h27, 8'h00, 8'h10, 8'h28);
  init_pkt(182, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1a, 8'h26, 8'h00, 8'h30, 8'h50);
  init_pkt(183, 8'h00, 8'h00, 8'h00, 8'h00, 8'h20, 8'h26, 8'h00, 8'h10, 8'h28);
  init_pkt(184, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1f, 8'h26, 8'h00, 8'h30, 8'h50);
  init_pkt(185, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1d, 8'h25, 8'h00, 8'h10, 8'h28);
  init_pkt(186, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1e, 8'h25, 8'h00, 8'h30, 8'h50);
  init_pkt(187, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1c, 8'h25, 8'h00, 8'h10, 8'h28);
  init_pkt(188, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1b, 8'h24, 8'h00, 8'h30, 8'h50);
  init_pkt(189, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1a, 8'h24, 8'h00, 8'h10, 8'h28);
  init_pkt(190, 8'h00, 8'h30, 8'h00, 8'h30, 8'h20, 8'h24, 8'h00, 8'h30, 8'h50);
  init_pkt(191, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1f, 8'h23, 8'h00, 8'h10, 8'h28);
  init_pkt(192, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1d, 8'h23, 8'h00, 8'h30, 8'h50);
  init_pkt(193, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1e, 8'h23, 8'h00, 8'h10, 8'h28);
  init_pkt(194, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1c, 8'h22, 8'h00, 8'h30, 8'h50);
  init_pkt(195, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1b, 8'h22, 8'h00, 8'h10, 8'h28);
  init_pkt(196, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1a, 8'h22, 8'h00, 8'h30, 8'h50);
  init_pkt(197, 8'h00, 8'h00, 8'h00, 8'h00, 8'h20, 8'h21, 8'h00, 8'h10, 8'h28);
  init_pkt(198, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1f, 8'h21, 8'h00, 8'h30, 8'h50);
  init_pkt(199, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1d, 8'h21, 8'h00, 8'h10, 8'h28);
  init_pkt(200, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1e, 8'h20, 8'h00, 8'h30, 8'h50);
  init_pkt(201, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1c, 8'h20, 8'h00, 8'h10, 8'h28);
  init_pkt(202, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1b, 8'h20, 8'h00, 8'h30, 8'h50);
  init_pkt(203, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1a, 8'h1f, 8'h00, 8'h10, 8'h28);
  init_pkt(204, 8'h00, 8'h00, 8'h00, 8'h00, 8'h20, 8'h1f, 8'h00, 8'h30, 8'h50);
  init_pkt(205, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1f, 8'h1f, 8'h00, 8'h10, 8'h28);
  init_pkt(206, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1d, 8'h1e, 8'h00, 8'h30, 8'h50);
  init_pkt(207, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1e, 8'h1e, 8'h00, 8'h10, 8'h28);
  init_pkt(208, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1c, 8'h1e, 8'h00, 8'h30, 8'h50);
  init_pkt(209, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1b, 8'h1d, 8'h00, 8'h10, 8'h28);
  init_pkt(210, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1a, 8'h1d, 8'h00, 8'h30, 8'h50);
  init_pkt(211, 8'h00, 8'h30, 8'h00, 8'h30, 8'h20, 8'h1d, 8'h00, 8'h10, 8'h28);
  init_pkt(212, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1f, 8'h1c, 8'h00, 8'h30, 8'h50);
  init_pkt(213, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1d, 8'h1c, 8'h00, 8'h10, 8'h28);
  init_pkt(214, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1e, 8'h1c, 8'h00, 8'h30, 8'h50);
  init_pkt(215, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1c, 8'h1b, 8'h00, 8'h10, 8'h28);
  init_pkt(216, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1b, 8'h1b, 8'h00, 8'h30, 8'h50);
  init_pkt(217, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1a, 8'h1b, 8'h00, 8'h10, 8'h28);
  init_pkt(218, 8'h00, 8'h00, 8'h00, 8'h00, 8'h20, 8'h1a, 8'h00, 8'h30, 8'h50);
  init_pkt(219, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1f, 8'h1a, 8'h00, 8'h10, 8'h28);
  init_pkt(220, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1d, 8'h1a, 8'h00, 8'h30, 8'h50);
  init_pkt(221, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1e, 8'h19, 8'h00, 8'h10, 8'h28);
  init_pkt(222, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1c, 8'h19, 8'h00, 8'h30, 8'h50);
  init_pkt(223, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1b, 8'h19, 8'h00, 8'h10, 8'h28);
  init_pkt(224, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1a, 8'h18, 8'h00, 8'h30, 8'h50);
  init_pkt(225, 8'h00, 8'h00, 8'h00, 8'h00, 8'h20, 8'h18, 8'h00, 8'h10, 8'h28);
  init_pkt(226, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1f, 8'h18, 8'h00, 8'h30, 8'h50);
  init_pkt(227, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1d, 8'h18, 8'h00, 8'h10, 8'h28);
  init_pkt(228, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1e, 8'h18, 8'h00, 8'h30, 8'h50);
  init_pkt(229, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1c, 8'h18, 8'h00, 8'h10, 8'h28);
  init_pkt(230, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1b, 8'h18, 8'h00, 8'h30, 8'h50);
  init_pkt(231, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1a, 8'h18, 8'h00, 8'h10, 8'h28);
  init_pkt(232, 8'h00, 8'h30, 8'h00, 8'h30, 8'h20, 8'h18, 8'h00, 8'h30, 8'h50);
  init_pkt(233, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1f, 8'h18, 8'h00, 8'h10, 8'h28);
  init_pkt(234, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1d, 8'h18, 8'h00, 8'h30, 8'h50);
  init_pkt(235, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1e, 8'h18, 8'h00, 8'h10, 8'h28);
  init_pkt(236, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1c, 8'h18, 8'h00, 8'h30, 8'h50);
  init_pkt(237, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1b, 8'h18, 8'h00, 8'h10, 8'h28);
  init_pkt(238, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1a, 8'h18, 8'h00, 8'h30, 8'h50);
  init_pkt(239, 8'h00, 8'h00, 8'h00, 8'h00, 8'h20, 8'h18, 8'h00, 8'h10, 8'h28);
  init_pkt(240, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1f, 8'h18, 8'h00, 8'h30, 8'h50);
  init_pkt(241, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1d, 8'h18, 8'h00, 8'h10, 8'h28);
  init_pkt(242, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1e, 8'h18, 8'h00, 8'h30, 8'h50);
  init_pkt(243, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1c, 8'h18, 8'h00, 8'h10, 8'h28);
  init_pkt(244, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1b, 8'h18, 8'h00, 8'h30, 8'h50);
  init_pkt(245, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1a, 8'h18, 8'h00, 8'h10, 8'h28);
  init_pkt(246, 8'h00, 8'h00, 8'h00, 8'h00, 8'h20, 8'h18, 8'h00, 8'h30, 8'h50);
  init_pkt(247, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1f, 8'h18, 8'h00, 8'h10, 8'h28);
  init_pkt(248, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1d, 8'h18, 8'h00, 8'h30, 8'h50);
  init_pkt(249, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1e, 8'h18, 8'h00, 8'h10, 8'h28);
  init_pkt(250, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1c, 8'h18, 8'h00, 8'h30, 8'h50);
  init_pkt(251, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1b, 8'h18, 8'h00, 8'h10, 8'h28);
  init_pkt(252, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1a, 8'h18, 8'h00, 8'h30, 8'h50);
  init_pkt(253, 8'h00, 8'h30, 8'h00, 8'h30, 8'h20, 8'h18, 8'h00, 8'h10, 8'h28);
  init_pkt(254, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1f, 8'h18, 8'h00, 8'h30, 8'h50);
  init_pkt(255, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1d, 8'h18, 8'h00, 8'h10, 8'h28);
  init_pkt(256, 8'h00, 8'h30, 8'h00, 8'h30, 8'h1e, 8'h18, 8'h00, 8'h30, 8'h50);
endtask

task noise_packet(int idx);
  $display("%t: packet", $time);
  packet_start(8'h01);
  packet_cont(packets[idx][0]);
  packet_cont(packets[idx][1]);
  packet_cont(packets[idx][2]);
  packet_cont(packets[idx][3]);
  packet_cont(packets[idx][4]);
  packet_cont(packets[idx][5]);
  packet_cont(packets[idx][6]);
  packet_cont(packets[idx][7]);
  packet_cont(packets[idx][8]);

  repeat (8*12500)              // next frame
    @(posedge clk) ;
endtask

initial #0 begin
  init_packets();

  res = 1;
  clk = 1;
  din = 8'hxx;
  ncs = 1;
  nwr = 1;
  cycle = 0;

  #2 @(posedge clk) ;
  res = 0;

  #318 @(posedge clk) ;

  for (int i = 9; i < 15; i++)
    noise_packet(i);

  $finish;
end

endmodule


// Local Variables:
// compile-command: "iverilog -g2012 -grelative-include -DUPD1771C_ROM_INIT_FROM_HEX -s noise_tb -o noise_tb.vvp ../upd1771c.sv noise_tb.sv && ./noise_tb.vvp"
// End:
