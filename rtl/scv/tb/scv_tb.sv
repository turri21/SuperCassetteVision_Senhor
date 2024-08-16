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

reg         rominit_active;
integer     rominit_fin;
reg         rominit_sel_boot, rominit_sel_chr;
reg [11:0]  rominit_addr;
reg [7:0]   rominit_data;
reg         rominit_valid;

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
   .RESB(~res),

   .ROMINIT_SEL_BOOT(rominit_sel_boot),
   .ROMINIT_SEL_CHR(rominit_sel_chr),
   .ROMINIT_ADDR(rominit_addr),
   .ROMINIT_DATA(rominit_data),
   .ROMINIT_VALID(rominit_valid),

   .VID_PCE(),
   .VID_DE(),
   .VID_HS(),
   .VID_VS(),
   .VID_RGB()
   );

initial begin
  res = 1;
  clk = 1;

  rominit_active = 0;
  rominit_sel_boot = 0;
  rominit_sel_chr = 0;
  rominit_valid = 0;
end

initial forever begin :ckgen
  #(0.25/14.318181) clk = ~clk; // 2 * 14.318181 MHz
end

always @(posedge clk) if (rominit_active) begin
integer code;
logic [7:0] data;
  code = $fread(data, rominit_fin, 0, 1);
  if (!$feof(rominit_fin)) begin
    rominit_data <= data;
    if (rominit_valid)
      rominit_addr <= rominit_addr + 1'd1;
    else begin
      rominit_addr <= 0;
      rominit_valid <= '1;
    end
  end
  else begin
    rominit_active <= 0;
    rominit_addr <= 'X;
    rominit_data <= 'X;
    rominit_valid <= 0;
  end
end

task rominit_boot;
  rominit_fin = $fopen("upd7801g.s01", "r");
  assert(rominit_fin != 0) else $finish;

  rominit_sel_boot = '1;
  rominit_active = '1;
  while (rominit_active)
    @(posedge clk) ;
  @(posedge clk) ;
endtask

initial #0 begin
`ifndef SCV_BOOTROM_INIT_FROM_HEX
  rominit_boot();
`endif

  #2 @(posedge clk) ;
  res = 0;
  @(posedge dut.cpu.M1) ; // align with first ins.

`ifdef FAST_MAIN
  // We're looping until C reaches 0 (inner loop).
  #40 @(posedge clk) ;
  assert(dut.cpu.pc == 16'h0016);
  dut.cpu.c = 1;

  // We're also looping until B reaches 0 (outer loop).
  #42 @(posedge clk) ;
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
