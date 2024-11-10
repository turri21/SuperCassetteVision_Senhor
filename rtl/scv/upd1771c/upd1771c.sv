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


logic [7:0]     db;
logic [7:0]     sdb;
logic [11:0]    ab;
wor [15:0]      pdb;

wire            md_64_32, md_tone_ie, md_ns_ie, md_nss,
                md_time_ie, md_ext_ie, md_out, md_if;

// TODO: Find names and homes for these.
wire n156 = '0; // TODO: T2 of TBLn?
wire n570 = '1; // TODO
wire n103 = ~(testmode | n570);
wire n594 = (resp /* | n585 | n775 | n2612*/ | (id_op_jmp_call & ~testmode) | cl_id_op_calln_dd | n723);
wire n723 = '0; // TODO
wire n678 = (pc_ctrl3 | cl_id_op_calln_dd) | ~n156;
wire n3304 = ~(clk4 & (id_op_tbln_calln_2 & ~testmode | id_op_retx));
wire n3321 = ~(clk4 & (id_aluop_Hp_n | id_aluop_11x));
wire n895 = '1; // TODO: ~(TS ^ NS)?


//////////////////////////////////////////////////////////////////////
// Reset, etc.

logic resp;
wire  leader, follower, testmode;
logic ch1d, ch2d;

always @(posedge CLK) begin
  resp <= (resp & ~(cp1p & RESB)) | ~RESB;
end

always @(posedge CLK) begin
  if (cp1)
    ch1d <= CH1;
  if (cp1 | clk4)
    ch2d <= CH2;
end

assign leader = ~ch1d & ~ch2d;
assign follower = ch1d & ~ch2d;
assign testmode = ~(leader | follower);


//////////////////////////////////////////////////////////////////////
// Clock generator

wire cp1p, cp1n;                // CLK / 8, phase 1, DC=3/8
wire cp2p, cp2n;                // CLK / 8, phase 2, DC=2/8
wire clk1;
wire clk2;                      // ROM clock - ground columns
wire clk3;
wire clk4;
wire clk5;

logic cp1, cp2;

logic [2:0] cgcnt;
logic [8:0] cgo;

initial begin
  cp1 = 0;
  cp2 = 0;
  cgcnt = 0;
end

always @(posedge CLK) begin
  cgcnt <= cgcnt + 1'd1;
end

always_comb begin
  case (cgcnt)
    3'd0: cgo = 9'b000_0_0_0000;
    3'd1: cgo = 9'b001_0_0_0000;
    3'd2: cgo = 9'b001_0_1_0010;
    3'd3: cgo = 9'b010_0_0_0000;
    3'd4: cgo = 9'b010_1_1_0100;
    3'd5: cgo = 9'b100_1_0_0000;
    3'd6: cgo = 9'b100_0_1_1000;
    3'd7: cgo = 9'b100_0_0_0001;
    default: cgo = 'X;
  endcase
end

// cp* are 1 CLK early, so that cp1/2 align with clk1-5.
assign cp1p = cgo[0];
assign cp1n = cgo[1];
assign cp2p = cgo[2];
assign cp2n = cgo[3];
assign clk1 = cgo[4];
assign clk2 = cgo[5];
assign clk3 = cgo[6];
assign clk4 = cgo[7];
assign clk5 = cgo[8];

always @(posedge CLK) begin
  cp1 <= (cp1 | cp1p) & ~cp1n;
  cp2 <= (cp2 | cp2p) & ~cp2n;
end


//////////////////////////////////////////////////////////////////////
// Instruction decoder

logic [15:0] id;

always_comb begin
  id = pdb;
end

wire id_set_a = ~|id[15:14] & id[10] & ~id[9]; // 00xx_x10x__xxxx
wire id_op_in_pb = ~|id[15:11] & id[10] & ~id[8] & id[1]; // 0000_01x0__xx1x
wire id_op_in_pa = ~|id[15:11] & id[10] & ~id[8] & id[0]; // 0000_01x0__xxx1
wire id_op_calln = ~|id[15:13] & &id[12:11] & id[3]; // 0001_1xxx__1000
wire id_op_tbln_calln_2 = ~|id[15:13] & &id[12:11]; // 0001_1xxx__xxxx
wire id_op_mvi_md1_n = ~|id[15:14] & &id[13:12] & id[8]; // 0011_xxx1__xxxx
wire id_aluop_notest_md1_n = id[15] & ~|id[14:12] & id[8]; // 1000_xxx1__xxxx
wire id_op_mvi_md0_n = ~|id[15:14] & id[13] & ~id[12] & id[8]; // 0010_xxx1__xxxx
wire id_op_mov_xchg_a_dst = ~|id[15:13] & id[12] & ~id[11] & id[2]; // 0001_0xxx__x1xx
wire id_aluop_A_n = id[15] & ~|id[14:12] & ~id[8]; // 1000_xxx0__xxxx
wire id_aluop_A_Rr = &id[15:14] & ~|id[13:12] & ~id[3]; // 1100_xxxx__0xxx
wire id_op_reti = ~|id[15:12] & id[11] & id[8]; // 0000_1xx1__xxxx
wire id_op_tbln_a_Rr = ~|id[15:13] & &id[12:11] & id[0]; // 0001_1xxx__xxx1
wire id_aluop_1x1 = id[15] & id[13]; // 1x1x_xxxx__xxxx
wire id_aluop_100 = id[15] & ~|id[14:13]; // 100x_xxxx__xxxx
wire id_op_adi_sbi_adi5_Rr_n = &id[15:13] & ~id[11] & ~id[9]; // 111x_0x0x__xxxx
wire id_op_xori = id_aluop_10x_1x0 & ~id[12] & &id[11:9]; // xxx0_111x__xxxx
wire id_op_adi_andi_sbi_ori = id_aluop_10x_1x0 & ~|id[12:11] ; // xxx0_0xxx__xxxx
wire id_op_not_aluop_or_rets = ~id_op_rets & ~id[15]; // 0xxx_xxxx__xxxx
wire id_op_rets = ~|id[15:12] & id[11] & ~id[8] & id[0]; // 0000_1xx0__xxx1
wire id_aluop_10x_1x0 = id_aluop_10x | id_aluop_1x0;
wire id_aluop_10x = id[15] & ~id[14]; // 10xx_xxxx__xxxx
wire id_aluop_1x0 = id[15] & ~id[13]; // 1x0x_xxxx__xxxx
wire id_aluop_10x_1x0_txnx = id_aluop_10x_1x0 & ~id[11]; // xxxx_0xxx__xxxx
wire id_aluop_txnx_Rr_n = &id[15:13] & ~id[12] & ~id[9]; // 1110_xx0x__xxxx
wire id_op_out_pb = ~|id[15:10] & id[2] & ~id[0]; // 0000_00xx__x1x0
wire id_op_out_pa = ~|id[15:10] & id[1]; // 0000_00xx__xx1x
wire id_op_jmp_call = ~id[15] & &id[14:13]; // 011x_xxxx__xxxx
wire id_op_call = ~id[15] & &id[14:12]; // 0111_xxxx__xxxx
wire id_op_retx = ~|id[15:12] & id[11]; // 0000_1xxx__xxxx
wire id_aluop_Hp_n = id[15] & ~id[14] & id[13] & ~id[8]; // 101x_xxx0__xxxx
wire id_aluop_11x = &id[15:14]; // 11xx_xxxx__xxxx
wire id_aluop_Rr_A_Hp_A = &id[15:14] & ~|id[13:12] & id[3]; // 1100_xxxx__1xxx
wire id_aluop_notest_Hp_n = id[15] & ~id[14] & id[13] & ~id[12] & ~id[8]; // 1010_xxx0__xxxx
wire id_aluop_notest_Rr_n = &id[15:13] & ~id[11]; // 111x_0xxx__xxxx
wire id_op_mvi_Rr_n = ~id[15] & id[14] & ~id[13]; // 010x_xxxx__xxxx
wire id_op_mov_xchg_Hp_Rr_x = ~|id[15:14] & id[12] & id[9]; // 00x1_xx1x__xxxx
wire id_aluop_Rr_n = &id[15:13]; // 111x_xxxx__xxxx
wire id_op_Rr_pdb8_4 = ~|id[15:13] & id[12] & ~(id[10] & ~id[3]); // 0001_xxxx__xxxx & ~xxxx_x1xx__0xxx
wire id_op_src_n_a = ~id[15] & id[13]; // 0x1x_xxxx__xxxx
wire id_op_src_n_b = ~id[15] & id[14]; // 01xx_xxxx__xxxx
wire id_op_set_H = ~|id[15:13] & id[12] & ~|id[11:10] & id[3]; // 0001_00xx__1xxx
wire id_aluop_notest_H_n = id[15] & ~id[14] & id[13] & ~id[12] & id[8]; // 1010_xxx1__xxxx
wire id_op_mvi_H_n = ~|id[15:14] & &id[13:11]; // 0011_1xxx__xxxx
wire id_aluop_sb = id[15] & id[10] & ~id[9]; // 1xxx_x10x__xxxx
wire id_op_mul2_3 = ~|id[15:11] & id[10] & id[8] & id[3]; // 0000_01x1__1xxx
wire id_op_not_aluop = ~id[15] & ~(id_op_mul2_3 | id_op_mix | id_op_mov_xchg_Hp_Rr_dst);
wire id_op_mix = ~|id[15:13] & id[12] & ~id[11] & id[10] & id[3];
wire id_op_mov_xchg_Hp_Rr_dst = ~|id[15:13] & id[12] & ~id[11] & id[9]; // 0001_0x1x__xxxx
wire id_op_000x_x0 = ~|id[15:13] & ~id[11]; // 000x_x0xx__xxxx
wire id_op_000 = ~|id[15:13]; // 000x_xxxx__xxxx
wire id_aluop_A_Rr_Hp = &id[15:14] & ~id[13] & ~id[3]; // 110x_xxxx__0xxx
wire id_get_a_clk4 = ~|id[15:11] & ~(~|id[10:9] & id[3]) & ~resp; // 0000_0xxx__xxxx & ~xxxx_x00x__1xxx & ~resp
wire id_get_a_clk3_a = ~|id[15:13] & id[12] & ~id[11] & id[0]; // 0001_0xxx__xxx1
wire id_get_a_clk3_b = &id[15:14] & ~id[13]; // 110x_xxxx__xxxx
wire id_get_a_clk3_c = id[15] & ~|id[14:13] & ~id[8]; // 100x_xxx0__xxxx
wire id_aluop_H_n = id[15] & ~id[14] & id[13] & id[8]; // 101x_xxx1__xxxx
wire id_get_h_clk3 = ~|id[15:13] & id[12] & ~id[11] & id[1]; // 0001_0xxx__xx1x
wire id_op_jmp_call_n_t2 = ~id[15] & &id[14:13] & ~cl_t1; // 011x_xxxx__xxxx & ~cl_t1
wire id_aluop_Rr_n_not_c5 = &id[15:13] & ~id[12]; // 1110_xxxx__xxxx
wire id_aluop_10x_1x0_sk_cb = id_aluop_10x_1x0 & ~id[9]; // xxxx_xx0x__xxxx & aluop_10x_1x0
wire id_aluop_10x_1x0_sk_z = id_aluop_10x_1x0 & id[9]; // xxxx_xx1x__xxxx & aluop_10x_1x0


//////////////////////////////////////////////////////////////////////
// Control logic

logic cl_id_op_calln_d, cl_id_op_calln_dd;
logic cl_id_op_tbln_a_Rr_d, cl_id_op_tbln_a_Rr_dd;
logic cl_skip_d, cl_skip_dd;
logic cl_id_op_out_pa_d;

wire cl_t1 = '0;
wire cl_pdb7_4_to_sdb7_4 = clk4 & n723;
wire cl_pdb11_8_to_sdb3_0 = clk4 & (resp | cl_t1 | (id_op_jmp_call & ~testmode));
wire cl_pdb15_8_to_db7_0 = clk4 & ~n678;
wire cl_pdb7_0_to_db7_0 = n678 & (cl_pdb11_8_to_sdb3_0 | (clk3 & id_aluop_1x1) | (clk4 & (id_op_src_n_a | id_op_src_n_b | id_aluop_100)));
wire cl_a_reg_en = ((cl_id_op_tbln_a_Rr_dd | id_aluop_A_Rr | id_op_reti | id_aluop_A_n | id_set_a) & cp2) | (id_op_mov_xchg_a_dst & clk4);
wire cl_op_clear_skip = id_op_adi_sbi_adi5_Rr_n | id_op_xori | id_op_adi_andi_sbi_ori | id_op_not_aluop_or_rets;
wire cl_skip_test_if_set = ~(id_op_rets | id_aluop_10x_1x0_txnx | id_aluop_txnx_Rr_n);
wire cl_md0_reg_en = resp | cl_md1_reg_en | id_op_mvi_md0_n; // Yes, cl_md1_reg_en is actually in here.
wire cl_md1_reg_en = resp | id_op_mvi_md1_n | id_aluop_notest_md1_n;
wire cl_sp_to_ram_a = id_op_call;
wire cl_spm1_to_ram_a = id_op_retx;
wire cl_pdb12_8_to_ram_a = id_op_mvi_Rr_n;
wire cl_pdb8_4_to_ram_a = id_aluop_Rr_n | id_op_Rr_pdb8_4;
wire cl_id_op_Hp_Rr_dst = id_aluop_Rr_A_Hp_A | id_aluop_Hp_n | id_aluop_notest_Rr_n | id_op_mvi_Rr_n | id_op_mov_xchg_Hp_Rr_x;
wire cl_h_reg_en = clk1 & ((cp2 & id_aluop_notest_H_n) | (clk4 & (id_op_mvi_H_n | id_op_set_H)));
wire cl_a_to_db = (clk3 & (id_get_a_clk3_a | id_get_a_clk3_b | id_get_a_clk3_c)) | (clk4 & id_get_a_clk4);
wire cl_h_to_db = (clk3 & id_get_h_clk3) | (clk4 & id_aluop_H_n);
wire cl_alu_c_to_db = clk5 & ~(id_op_in_pa | id_op_in_pb | id_op_jmp_call_n_t2 | n103 | cl_id_op_calln_dd | (id_op_jmp_call & ~testmode));

always @(posedge CLK) begin
  if (cp2n) begin
    cl_id_op_calln_d <= id_op_calln & ~testmode;
    cl_id_op_tbln_a_Rr_d <= id_op_tbln_a_Rr;
    cl_skip_d <= cl_skip;
    cl_id_op_out_pa_d <= id_op_out_pa;
  end
  if (cp1p) begin
    cl_id_op_calln_dd <= cl_id_op_calln_d;
    cl_id_op_tbln_a_Rr_dd <= cl_id_op_tbln_a_Rr_d;
    cl_skip_dd <= cl_skip_d;
  end
end

// Instruction skip logic
wire cl_skip = cl_skip_a; // TODO: add id_op_reti
wire cl_skip_test_out =
     ((id_aluop_Rr_n_not_c5 | id_aluop_10x_1x0_sk_cb) & alu_co) |
     (id_aluop_10x_1x0_sk_z & alu_c_zero)/* |
     (n906 & n910) |
     (n2986 & n911)*/;
wire cl_skip_test_failed = cl_skip_test_out ^ cl_skip_test_if_set;
wire cl_skip_a = ~(cl_op_clear_skip | cl_skip_test_failed);


//////////////////////////////////////////////////////////////////////
// Arithmetic/Logic Unit

logic [7:0] alu_a;              // input A (from TEMP1)
logic [7:0] alu_b;              // input B (from TEMP2)
logic [7:0] alu_c;              // output (S)
logic       alu_co;
wire        alu_c_zero;

wire alu_op_zero_a_lo = id_op_not_aluop;
wire alu_op_zero_a_hi = alu_op_zero_a_lo | id_op_000;
wire alu_op_sub = id_op_mix ? ~n895 : (id_aluop_sb | id_op_000x_x0);

wire alu_temp1_first = ~(id_aluop_A_Rr_Hp | id_aluop_100);
wire alu_db_to_temp1 = (clk3 & alu_temp1_first) | (clk4 & ~alu_temp1_first);

always @(posedge CLK) begin
  // alu_db_to_temp1/2 are high before and during clk1. And clk1
  // drives TEMP1/2 to A/B.
  if (clk1) begin
    if (alu_db_to_temp1)
      alu_a <= db;
    else
      alu_b <= db;
  end
  if (alu_op_zero_a_lo)
    alu_a[3:0] <= '0;
  if (alu_op_zero_a_hi)
    alu_a[7:4] <= '0;
end

always @* begin
  if (alu_op_sub)
    {alu_co, alu_c} = alu_b - alu_a;
  else
    {alu_co, alu_c} = alu_a + alu_b;
end

assign alu_c_zero = alu_c == '0;


//////////////////////////////////////////////////////////////////////
// pc: Program counter

logic [11:0] pc, pcin, pcn;
logic [11:0] abn, abadd;

wire pc_ctrl1 = clk4 & ~(id_op_tbln_calln_2 & ~testmode | n103 | n594);
wire pc_ctrl3 = '1; // TODO
wire pc_ctrl4 = '1; // TODO
wire pc_load_int_vec = '0; // TODO
wire pc_load_sdb3_0_db7_0 = clk4 & n594;
wire pc_load_sdb4_0_db7_1 = '0; // TODO
wire pc_abadd_cin = ~n103;
wire pc_pcin_to_abn = 1'b1; // TODO

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
//assign rom_zero = ~(testmode | ~(resp | n103 | cl_skip_dd));
assign rom_zero = resp | (~testmode & (n103 | cl_skip_dd));
assign rom_oe = ~leader;

always @(posedge CLK) begin
  rom_rbuf <= rom[ab[8:0]];
end

always @(posedge CLK) if (cp1p) begin
  rom_do <= (|ab[11:9]) ? '0 : rom_rbuf;
end

assign pdb = (rom_oe & ~rom_zero) ? rom_do : '0;


//////////////////////////////////////////////////////////////////////
// CPU-programmable registers

logic [9:0] md;
logic [7:0] a;
logic [5:0] h;
logic [2:0] sp;

initial begin
  h = '0; // else ram_col[1] is X
end

always @(posedge CLK) begin
  if (cl_md0_reg_en)
    {md[9], md[8], md[4:0]} <= db[6:0];
  if (cl_md1_reg_en)
    md[7:5] <= {(resp | db[7]), db[6:5]};
end

assign md_64_32 = md[0];
assign md_tone_ie = md[1];
assign md_ns_ie = md[2];
assign md_nss = md[3];
assign md_time_ie = md[4];
assign md_ext_ie = md[5];
assign md_out = md[6];
assign md_if = md[7];


always @(posedge CLK) begin
  if (cl_a_reg_en)
    a <= db;
end

always @(posedge CLK) begin
  if (cl_h_reg_en)
    h <= db;
end

always @(posedge CLK) if (cp1p) begin
  if (resp)
    sp <= 0;
  else if (cl_sp_to_ram_a)
    sp <= sp + 1'd1;
  else if (cl_spm1_to_ram_a)
    sp <= sp - 1'd1;
end


//////////////////////////////////////////////////////////////////////
// 64 byte SRAM: 32 columns x 16 rows

// Address select
logic [3:0] ram_row;            // Row address select
logic [1:0] ram_col;            // Column address select

always @* begin
  ram_row = 'X;
  ram_col = 'X;
  if (cl_spm1_to_ram_a | cl_sp_to_ram_a) begin
    ram_row[3] = 1'b1;
    ram_col = 1'b0;
    ram_row[2:0] = cl_spm1_to_ram_a ? (sp - 1'd1) : sp;
  end
  else if (cl_pdb12_8_to_ram_a | cl_pdb8_4_to_ram_a) begin
    ram_row[3] = 1'b0;
    {ram_col[0], ram_row[2:0], ram_col[1]} = cl_pdb12_8_to_ram_a ? pdb[12:8] : pdb[8:4];
  end
  else /*if (cl_h_to_ram_a)*/
    {ram_row[3], ram_col[0], ram_row[2:0], ram_col[1]} = h;
end

wire ram_lr_col_sel = ram_col[0];  // left/right col. pair select: 0=left
wire ram_left_sel = ~ram_col[1];   // left array select
wire ram_right_sel = ram_col[1];   // right array select

// Left half of array (cols 0-15): R/W port == db
logic [7:0] ram_left_mem [2][16];
logic [7:0] ram_left_rbuf;
logic [7:0] ram_left_wbuf;
wire        ram_left_write_en;
wire        ram_left_db_oe;

always @(posedge CLK) begin
  if (ram_left_write_en)
    ram_left_mem[ram_lr_col_sel][ram_row] <= ram_left_wbuf;
  ram_left_rbuf <= ram_left_mem[ram_lr_col_sel][ram_row];
end

assign ram_left_write_en = cp2 & ~(ram_right_db_ie & (~cl_id_op_Hp_Rr_dst | ram_left_sel));
assign ram_left_db_oe = ~(n3304 & (ram_left_sel | n3321));

assign ram_left_wbuf = db;

// Right half of array (cols 16-31): R/W port == db or sdb
logic [7:0] ram_right_mem [2][16];
logic [7:0] ram_right_rbuf;
logic [7:0] ram_right_wbuf;
wire        ram_right_write_en;
wire        ram_right_db_ie;
wire        ram_right_db_oe;
wire        ram_right_sdb_oe = 0;; // TODO

always @(posedge CLK) begin
  if (ram_right_write_en)
    ram_right_mem[ram_lr_col_sel][ram_row] <= ram_right_wbuf;
  ram_right_rbuf <= ram_right_mem[ram_lr_col_sel][ram_row];
end

assign ram_right_write_en = cp2 & ~(ram_right_db_ie & (~cl_id_op_Hp_Rr_dst | ram_right_sel));
assign ram_right_db_ie = ~cl_sp_to_ram_a;
assign ram_right_db_oe = ~(ram_right_sel | n3321);

assign ram_right_wbuf = ram_right_db_ie ? db : sdb;


//////////////////////////////////////////////////////////////////////
// I/O ports

logic [7:0] pai, pbi;
logic [7:0] pao, pbo;
logic [7:0] pbi_reg;
logic [7:0] pao_reg, pbo_reg;
logic [7:0] pao_reg_p, pbo_reg_p;

wire io_pabx_pad_pdb_pax_db_out_en, io_pabx_out_reg_pad_en,
     io_pax_out_pbx_pdb_pad_en, io_pax_pdb_out_en;
wire io_pax_out_reg_latch_en;
wire io_pbx_out_reg_ce;
wire io_pax_noe, io_pbx_noe, io_pbx7_3_noe, io_pbx2_0_noe;
wire io_pax_pad_db_en, io_pbx_pad_db_en;
wire io_ext_latch_en, io_ext_latch_in, io_ext_latch;

assign io_pabx_pad_pdb_pax_db_out_en = leader;
assign io_pabx_out_reg_pad_en = ~testmode;
assign io_pax_out_pbx_pdb_pad_en = ~io_pabx_out_reg_pad_en;
assign io_pax_pdb_out_en = ~io_pabx_pad_pdb_pax_db_out_en;
assign io_pax_pad_db_en = id_op_in_pa & clk5;
assign io_pbx_pad_db_en = id_op_in_pb & clk5;
assign io_pax_noe = '0; // TODO
assign io_pbx_noe = ~((md_out & follower) | io_pax_out_pbx_pdb_pad_en);
assign io_pbx7_3_noe = io_pbx_noe;
assign io_pbx2_0_noe = io_pbx_noe & ~leader & md_if;

assign io_ext_latch_in = ~(io_pbx7_3_noe ? pbi[6] : pbo_reg[5]);
assign io_ext_latch_en = ~pbi[7];
assign io_ext_latch = ~leader & md_if & io_ext_latch_en & io_ext_latch_in;

assign io_pbx_out_reg_ce = id_op_out_pb;
assign io_pax_out_reg_latch_en = cl_id_op_out_pa_d | io_ext_latch;

always @(posedge CLK) begin
  if (cp2n)
    pbo_reg_p <= io_pbx_out_reg_ce ? db : pbo_reg;
  if (cp1p)
    pbo_reg <= pbo_reg_p;
end


assign pai = (PA_OE & PA_O) | (~PA_OE & PA_I);
assign pbi = (PB_OE & PB_O) | (~PB_OE & PB_I);

assign pao = io_pabx_out_reg_pad_en ? pao_reg :
             (io_pax_pdb_out_en ? pdb[15:8] : db);
assign pbo = io_pabx_out_reg_pad_en ? pbo_reg : pdb[7:0];

assign PA_O = pao;
assign PB_O = pbo;
assign PA_OE = {8{~io_pax_noe}};
assign PB_OE = {{5{~io_pbx7_3_noe}}, {3{~io_pbx2_0_noe}}};


//////////////////////////////////////////////////////////////////////
// Internal buses

logic [7:0]     db_d;
logic [7:0]     sdb_d;

// db: Data bus
always @* begin
  db = db_d;
  if (cl_pdb15_8_to_db7_0)  db = pdb[15:8];
  if (cl_pdb7_0_to_db7_0)   db = pdb[7:0];
  //if (n699)                 db = md[7:0];
  if (cl_a_to_db)           db = a;
  if (cl_h_to_db)           db = h;
  if (cl_alu_c_to_db)       db = alu_c;
  if (ram_left_db_oe)       db = ram_left_rbuf;
  if (ram_right_db_oe)      db = ram_right_rbuf;
  if (io_pax_pad_db_en)     db = pai[7:0];
  if (io_pbx_pad_db_en)     db = pbi_reg[7:0];
end

// sdb: Special data bus
always @* begin
  sdb = sdb_d;
  if (cl_pdb7_4_to_sdb7_4)  sdb[7:4] = pdb[7:4];
  if (cl_pdb11_8_to_sdb3_0) sdb[3:0] = pdb[11:8];
  if (ram_right_sdb_oe)     sdb = ram_right_rbuf;
end

always @(posedge CLK) begin
  db_d <= db;
  sdb_d <= sdb;
end


endmodule
