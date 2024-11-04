// NEC uPD1771C - a functional implementation
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

// References:
// . https://github.com/mamedev/mame/blob/master/src/devices/sound/upd1771.cpp - MAME's emulation
// . https://siliconpr0n.org/map/nec/d1771c-017/mcmaster_mz_mit20x/ - photomicrograph of D1771C-017 die
// . http://reverendgumby.gitlab.io/visuald1771c - JavaScript simulator derived from above die shot

`timescale 1us / 1ns

module upd1771c
  (
   input        CLK,
   input        RESB,

   input        CH1,
   input        CH2,

   input [7:0]  PA_I,
   output [7:0] PA_O,
   output [7:0] PA_OE,
   input [7:0]  PB_I,
   output [7:0] PB_O,
   output [7:0] PB_OE,

   output       PCM_NEG,
   output [7:0] PCM_OUT
   );


wor [7:0]       sdb, db;
logic [11:0]    ab;
wor [15:0]      pdb;

// TODO: Find names and homes for these.
wire n156 = '0;
wire n570 = '1;
wire n103 = ~(testmode | n570);
wire n594 = ~n690;
wire n723 = '0;
wire n690 = ~(resp /* | n585 | n775 | n2612 | n696 | cl_id_op_calln_dd | n723*/);
wire n696 = '0;
wire n689 = ~(pc_ctrl3 | cl_id_op_calln_dd);
wire n678 = ~(n689 & n156);
wire n2694 = ~(id_op_tbln_calln_2 | n103 | n594);
wire n791 = '1;

always @(posedge CLK) begin
  if (cp1p) begin
    ;
  end
  if (cp2p) begin
  end
end


//////////////////////////////////////////////////////////////////////
// Reset, etc.

logic resp;
wire  testmode;

always @(posedge CLK) begin
  resp <= (resp & ~(cp1p & RESB)) | ~RESB;
end

assign testmode = CH2;

//////////////////////////////////////////////////////////////////////
// Clock generator

wire cp1p, cp1n;                // CLK / 8, phase 1, DC=3/8
wire cp2p, cp2n;                // CLK / 8, phase 2, DC=2/8
wire clk1;
wire clk2;                      // ROM clock - ground columns
wire clk3;
wire clk4;
wire clk5;

logic [2:0] cgcnt;
logic [8:0] cgo;

initial begin
  cgcnt = 0;
end

always @(posedge CLK) begin
  cgcnt <= cgcnt + 1'd1;
end

always_comb begin
  case (cgcnt)
    3'd0: cgo = 9'b000_0_0_0001;
    3'd1: cgo = 9'b001_0_0_0000;
    3'd2: cgo = 9'b001_0_1_0000;
    3'd3: cgo = 9'b010_0_0_0010;
    3'd4: cgo = 9'b010_1_1_0000;
    3'd5: cgo = 9'b100_1_0_0100;
    3'd6: cgo = 9'b100_0_1_0000;
    3'd7: cgo = 9'b100_0_0_1000;
    default: cgo = 'X;
  endcase
end

assign cp1p = cgo[0];
assign cp1n = cgo[1];
assign cp2p = cgo[2];
assign cp2n = cgo[3];
assign clk1 = cgo[4];
assign clk2 = cgo[5];
assign clk3 = cgo[6];
assign clk4 = cgo[7];
assign clk5 = cgo[8];


//////////////////////////////////////////////////////////////////////
// I/O ports

logic [7:0] pao, pbo;
logic [7:0] pao_reg, pbo_reg;

wire io_pabx_pad_pdb_pax_db_out_en = '0;
wire io_pabx_out_reg_pad_en = '0;
wire io_pax_pdb_out_en = '1;
wire io_pax_noe = '0;
wire io_pbx7_3_noe = '0;
wire io_pbx2_0_noe = '0;

assign pao = io_pabx_out_reg_pad_en ? pao_reg :
             (io_pax_pdb_out_en ? pdb[15:8] : db);
assign pbo = io_pabx_out_reg_pad_en ? pbo_reg : pdb[7:0];

assign PA_O = pao;
assign PB_O = pbo;
assign PA_OE = {8{~io_pax_noe}};
assign PB_OE = {{5{~io_pbx7_3_noe}}, {3{~io_pbx2_0_noe}}};


//////////////////////////////////////////////////////////////////////
// Instruction decoder

wire id_op_calln = '0;
wire id_op_tbln_calln_2 = '0;
wire n1351 = '0;
wire n1422 = '0;
wire n1426 = '0;
wire n1430 = '0;


//////////////////////////////////////////////////////////////////////
// Control logic

logic cl_id_op_calln_d, cl_id_op_calln_dd;

wire cl_t1 = '0;
wire cl_pdb7_4_to_sdb7_4 = clk4 & n723;
wire cl_pdb11_8_to_sdb3_0 = clk4 & (testmode | cl_t1 | n696);
wire cl_pdb15_8_to_db7_0 = clk4 & ~n678;
wire cl_pdb7_0_to_db7_0 = n678 & (cl_pdb11_8_to_sdb3_0 | (clk3 & n1351) | (clk4 & (n1422 | n1426 | n1430)));

always @(posedge CLK) begin
  if (cp2p) begin
    cl_id_op_calln_d <= id_op_calln;
  end
  if (cp1p) begin
    cl_id_op_calln_dd <= cl_id_op_calln_d;
  end
end


//////////////////////////////////////////////////////////////////////
// Internal buses

// db: Data bus
assign db = cl_pdb15_8_to_db7_0 ? pdb[15:8] : '0;
assign db = cl_pdb7_0_to_db7_0 ? pdb[7:0] : '0;

// sdb: Special data bus
assign sdb[7:4] = cl_pdb7_4_to_sdb7_4  ? pdb[7:4]  : '0;
assign sdb[3:0] = cl_pdb11_8_to_sdb3_0 ? pdb[11:8] : '0;


//////////////////////////////////////////////////////////////////////
// pc: Program counter

logic [11:0] pc, pcin, pcn;
logic [11:0] abn, abadd;

wire pc_ctrl1 = clk4 & n2694;
wire pc_ctrl3 = '1;
wire pc_ctrl4 = '1;
wire pc_load_int_vec = '0;
wire pc_load_sdb3_0_db7_0 = clk4 & n594;
wire pc_load_sdb4_0_db7_1 = '0;
wire pc_abadd_cin = ~n103;
wire pc_pcin_to_abn = 1'b1;

always @(posedge CLK) if (clk1) begin
  pc <= pcn;
  ab <= abn;
end

always @* begin
  pcn = (clk3 & pc_ctrl3) ? abadd : pc;
  abn = (clk4 & pc_pcin_to_abn) ? pcin : ab;
end

always @(posedge CLK) begin
  if (pc_load_sdb3_0_db7_0)
    pcin <= {sdb[3:0], db[7:0]};
  else if (pc_load_sdb4_0_db7_1)
    pcin <= {sdb[4:0], db[7:1]};
  else if (pc_load_int_vec)
    pcin <= 0; //TODO
  else if (pc_ctrl1)
    pcin <= pc;
end

always_comb
  abadd = ab + pc_abadd_cin;


//////////////////////////////////////////////////////////////////////
// Program ROM

logic [15:0] rom [1 << 9];
logic [15:0] rom_rbuf, rom_do;
wire         rom_oe, rom_zero;

initial begin
  $readmemh("rom.hex", rom);
end

// Change rom_zero from silicon, to clear PC even in testmode
//assign rom_zero = ~(testmode | ~(resp | n103 | n791));
assign rom_zero = resp | (~testmode & (n103 | n791));
assign rom_oe = ~io_pabx_pad_pdb_pax_db_out_en;

always @(posedge CLK) begin
  rom_rbuf <= rom[ab[8:0]];
end

always @(posedge CLK) if (cp1p) begin
  rom_do <= (rom_zero | |ab[11:9]) ? '0 : rom_rbuf;
end

assign pdb = rom_oe ? rom_do : '0;


endmodule
