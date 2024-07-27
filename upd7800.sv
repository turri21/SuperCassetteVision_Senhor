// NEC uPD7800 - a trivial implementation
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

// References:
// . https://gist.githubusercontent.com/BlockoS/4c4ae33f7571ec48a4b2d3c264aee9f1/raw/80eff532a457ad2cef4dbc78462af69fe8a1efb3/uPD78c06_Instruction_Set.txt
// . https://forums.bannister.org/ubbthreads.php?ubb=showflat&Number=38637 - opcode list, other details
// . https://github.com/mamedev/mame/blob/master/src/devices/cpu/upd7810/upd7810.cpp - MAME's emulation
// . http://www.bitsavers.org/components/nec/_dataBooks/1981_NEC_Microcomputer_Catalog.pdf - includes uDP7801 data sheet, many other chips
// . http://takeda-toshiya.my.coocan.jp/scv/index.html - EPOCH Super Cassette Vision emulator for Win32 / uPD7801 tiny disassembler


`timescale 1us / 1ns

module upd7800
  (
   input         CLK,
   input         CP1_POSEDGE, // clock phase 1, +ve edge
   input         CP1_NEGEDGE, //  "             -ve edge
   input         CP2_POSEDGE, // clock phase 2, +ve edge
   input         CP2_NEGEDGE, //  "             -ve edge
   input         RESETB, // reset (active-low)
   output [15:0] A,
   input [7:0]   DB_I,
   output [7:0]  DB_O,
   output        DB_OE,
   output        M1 // opcode fetch cycle
   );

`define psw_z  psw[6]           // Zero
`define psw_sk psw[5]           // Skip
`define psw_hc psw[4]           // Half Carry
`define psw_l1 psw[3]           // Byte instruction string effect
`define psw_l0 psw[2]           // Word instruction string effect
`define psw_cy psw[0]           // Carry

`include "uc-types.svh"

wire         resp;
wire         cp1p, cp2p, cp2n;
wire [15:0]  pcl, pch;
wire [7:0]   db;

reg          resg;
reg          cp2;
reg [7:0]    psw;
reg [15:0]   pc, upc, npc;
reg [10:0]   ir;
reg          ie;                // interrupt enable flag
reg [15:0]   aor;
reg [7:0]    dor;
reg [7:0]    rfo, idb;
reg [15:0]   ab;
reg [7:0]    ai, bi, ibi, co;
reg          addc, notbi, pdah, pdal, pdac, cco, cho;

s_uc         uc;

reg          cl_pc_ab;
reg          cl_idb_pcl, cl_idb_pch;
reg          cl_idb_ir, cl_ui_ir;
reg          cl_ui_ie;
reg          cl_abl_aor, cl_abh_aor, cl_ab_aor;
reg          cl_pc_inc;
reg          cl_sums_cco, cl_carry, cl_one_addc, cl_c_addc, cl_bi_not,
             cl_bi_dah, cl_bi_dal, cl_pdas;
reg          cl_clrs, cl_sums, cl_ors, cl_ands, cl_eors, cl_asls, cl_rols,
             cl_lsrs, cl_rors;


//////////////////////////////////////////////////////////////////////
// Clocking

assign cp1p = CP1_POSEDGE;
assign cp2p = CP2_POSEDGE;
assign cp2n = CP2_NEGEDGE;

initial begin
  cp2 = 0;
end

always_ff @(posedge CLK) begin
  cp2 <= (cp2 & ~cp2n) | cp2p;
end


//////////////////////////////////////////////////////////////////////
// Reset and interrupts

initial begin
  resg = 0;
end

assign resp = ~RESETB;

always_ff @(posedge CLK) begin
  if (cp1p) begin
    resg <= resp;
  end
end


//////////////////////////////////////////////////////////////////////
// External interface

assign A = aor;

assign M1 = uc.m1;


//////////////////////////////////////////////////////////////////////
// Registers

// psw: processor status word
always @(posedge CLK) begin
  if (resg) begin
    psw <= 0;
  end
  else if (cp2n) begin
/* -----\/----- EXCLUDED -----\/-----
    if (cl_idb_psw)
      psw <= idb;

    if (cl_idbz_z)
      `psw_z <= ~|idb;

    if (cl_cco_c)
      `psw_c <= cco;
    if (cl_zero_c)
      `psw_c <= 1'b0;
    if (cl_one_c)
      `psw_c <= 1'b1;
 -----/\----- EXCLUDED -----/\----- */
  end
end

// pc: program ("P") counter
always @(posedge CLK) begin
  if (resg) begin
    pc <= 0;
  end
  else if (cp2p) begin
    pc <= npc;
  end
end

assign pcl = pc[7:0];
assign pch = pc[15:8];

// "updated" pc (change part or all)
always @(posedge CLK) begin
  if (cp1p) begin
    upc <= pc;

    if (cl_idb_pcl)
      upc[7:0] <= idb;
    if (cl_idb_pch)
      upc[15:8] <= idb;
  end
end

// "next" pc (increment)
always @* begin
  npc = upc;

  if (cl_pc_inc)
    npc = npc + 1;
end

// ir: instruction register
always @(posedge CLK) begin
  if (cp2n) begin
    if (cl_idb_ir) begin
      ir[7:0] <= idb;
    end
    if (cl_ui_ir) begin
      ir[10:8] <= uc.idx[2:0];
    end
  end
end

// ie: interrupt enable flag
always @(posedge CLK) begin
  if (resg) begin
    ie <= 1'b0;
  end
  else if (cp2n) begin
    if (cl_ui_ie) begin
      ie <= uc.idx[0];
    end
  end
end

// aor: address bus output register
// register latches on cp1p
always @(posedge CLK) begin
  if (cp1p) begin
    if (cl_abl_aor)
      aor[7:0] <= ab[7:0];
    else if (cl_abh_aor)
      aor[15:8] <= ab[15:8];
    else if (cl_ab_aor)
      aor <= ab[15:0];
  end
end

// dor: data output register
// register latches on cp1p
always @(posedge CLK) begin
  if (cp1p) begin
    dor <= idb;
  end
end


//////////////////////////////////////////////////////////////////////
// Internal buses

// rfo: register file output
always @* begin
  case (uc.rfs)
    URFS_PCL: rfo = pcl;
    URFS_PCH: rfo = pch;
    default: rfo = 8'hxx;
  endcase
end

// idb: internal data bus
always @* begin
  case (uc.idbs)
    UIDBS_0: idb = 0;
    UIDBS_RF: idb = rfo;
    UIDBS_DB: idb = DB_I;
    UIDBS_IR5: idb = {3'b000, ir[4:0]};
    UIDBS_CO: idb = co;
    default: idb = 8'hxx;
  endcase
end

// ab: (internal) address bus
always_comb begin
  case ({cl_pc_ab})
    'b1: ab = pc;
    default: ab = 16'hxxxx;
  endcase
end


//////////////////////////////////////////////////////////////////////
// ALU

// Inputs
always @(posedge CLK) begin
  if (uc.lts == ULTS_AI) begin
    ai <= idb;
  end
  if (uc.lts == ULTS_BI) begin
    bi <= idb;
  end
end

always @* addc = (cl_carry & cco) | cl_one_addc | (cl_c_addc & `psw_cy);
always @* notbi = cl_bi_not;
always @* pdah = (`psw_cy ^ cl_pdas) | (ai > 8'h99);
always @* pdal = (`psw_hc ^ cl_pdas) | (ai[3:0] > 4'h9);
always @* pdac = (~cl_pdas & (`psw_cy | pdah)) | (cl_pdas & `psw_cy & ~pdah);

always @* begin
  ibi = bi;
  // DAA/DAS adjust constants
  if (cl_bi_dah & pdah)
    ibi = 8'h60;
  if (cl_bi_dal & pdal)
    ibi = 8'h06;
  ibi = ibi ^ {8{notbi}};
end

// Maths
always @(posedge CLK) if (cp2n) begin
  if (cl_sums) begin :sums
  reg [4:0] hsum, lsum;
    lsum = ai[3:0] + ibi[3:0] + {3'b0, addc};
    hsum = ai[7:4] + ibi[7:4] + {3'b0, lsum[4]};
    co <= {hsum[3:0], lsum[3:0]};
    if (cl_sums_cco)
      cco <= (cl_bi_dah) ? pdac : hsum[4];
    //cvo <= (ai[7] == ibi[7]) & (ai[7] != hsum[3]);
    cho <= lsum > 5'd9;
  end
  else if (cl_ors)
    co <= ai | ibi;
  else if (cl_ands)
    co <= ai & ibi;
  else if (cl_eors)
    co <= ai ^ ibi;
  else if (cl_asls | cl_rols)
    {cco, co} <= {ai[7:0], addc & cl_rols};
  else if (cl_lsrs | cl_rors)
    {co, cco} <= {addc & cl_rors, ai[7:0]};
end


//////////////////////////////////////////////////////////////////////
// Microcode

s_uc    uram [64];
e_uaddr uptr, uptr_next;
e_uaddr at;

initial begin
  $readmemb("uram.mem", uram);
end

always_ff @(posedge CLK) begin
  if (cp2n) begin
    uc <= uram[uptr];
  end
end

always @* begin
  uptr_next = uptr;

  case (uc.bm)
    UBM_ADV: uptr_next = e_uaddr'(uptr_next + 1'd1);
    UBM_DA: uptr_next = uc.nua;
    UBM_AT: uptr_next = e_uaddr'(at);
    default: ;
  endcase
end

always_ff @(posedge CLK) begin
  if (resg) begin
    uptr <= UA_FETCH_IR1_T1;
  end
  else if (cp2p) begin
    uptr <= uptr_next;
  end
end


//////////////////////////////////////////////////////////////////////
// Microcode address generator

// Ugly hack to get the ball rolling...
e_uaddr at_lut [2048];

initial begin
int i;
  // Illegal opcode default: fetch new opcode
  for (i = 0; i < 2048; i++)
    at_lut[i] = UA_FETCH_IR1_T1;

`include "uc-at.svh"
end

// seemingly redundant typecast makes iverilog happy
always @* at = e_uaddr'(at_lut[ir]);


//////////////////////////////////////////////////////////////////////
// Control logic

initial cl_abl_aor = 0;
initial cl_abh_aor = 0;
always @* cl_ab_aor = uc.pc_ab;
always @* cl_idb_pcl = (uc.lts == ULTS_RF) & (uc.rfs == URFS_PCL);
always @* cl_idb_pch = (uc.lts == ULTS_RF) & (uc.rfs == URFS_PCH);
always @* cl_idb_ir = uc.irl;
always @* cl_ui_ir = uc.irl;
always @* cl_ui_ie = uc.lts == ULTS_IE;
always @* cl_pc_ab = uc.pc_ab;
always @* cl_pc_inc = uc.pc_inc;
initial cl_sums_cco = 1'b1;
always @* cl_carry = uc.cis == UCIS_CO;
always @* cl_one_addc = uc.cis == UCIS_1;
always @* cl_c_addc = uc.cis == UCIS_PSW_CY;
initial cl_bi_not = 0;
initial cl_bi_dah = 0;
initial cl_bi_dal = 0;
initial cl_pdas = 0;
initial cl_clrs = 0;
always @* cl_sums = uc.aluop == UAO_SUM;
initial cl_ors = 0;
initial cl_ands = 0;
initial cl_eors = 0;
initial cl_asls = 0;
initial cl_rols = 0;
initial cl_lsrs = 0;
initial cl_rors = 0;

endmodule
