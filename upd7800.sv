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
wire         t0;                // next machine cycle
wire [15:0]  pcl, pch;
wire [7:0]   db;

reg          resg;
reg          cp2;
reg          t1, t2, t3, t4;    // machine cycle (step)
reg [1:0]    tx;
reg [7:0]    psw;
reg [15:0]   pc, upc, npc;
reg [10:0]   ir;
reg          ie;                // interrupt enable flag
reg [15:0]   aor;
reg [7:0]    dor;
reg [7:0]    idb;
reg [15:0]   ab;

s_uc         uc;

reg          cl_db_idb;
reg          cl_idb_pcl, cl_idb_pch;
reg          cl_idb_ir, cl_ui_ir;
reg          cl_ui_ie;
reg          cl_abl_aor, cl_abh_aor, cl_ab_aor;
reg          cl_pc_inc;
reg          cl_uc_final;

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

  if (resg) begin
    t1 <= 1'b1;
    {t2, t3, t4} <= 0;
  end
  else if (cp2n) begin
    t1 <= t0;
    t2 <= t1;
    t3 <= t2;
    t4 <= t3 & ~t0;
  end
end

always_comb begin
  case (1'b1)
    t1: tx = 2'd0;
    t2: tx = 2'd1;
    t3: tx = 2'd2;
    t4: tx = 2'd3;
    default: tx = 2'dx;
  endcase
end

assign t0 = resg | (t3 & ~cl_idb_ir) | t4;


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
    if (cl_pc_inc)
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

// idb: internal data bus
always_comb begin
  case ({cl_db_idb})
    'b1: idb = DB_I;
    default: idb = 8'hxx;
  endcase
end

// ab: (internal) address bus
always @* ab = pc;


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
  uptr_next = UA_FETCH_IR1;

  case (uc.bm)
    UBM_AT: uptr_next = e_uaddr'(at);
    default: ;
  endcase
end

always_ff @(posedge CLK) begin
  if (resg) begin
    uptr <= UA_FETCH_IR1;
  end
  else if (cp1p & cl_uc_final) begin
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
    at_lut[i] = UA_FETCH_IR1;

`include "uc-at.svh"
end

// seemingly redundant typecast makes iverilog happy
always @* at = e_uaddr'(at_lut[ir]);


//////////////////////////////////////////////////////////////////////
// Control logic

initial cl_abl_aor = 0;
initial cl_abh_aor = 0;
always @* cl_ab_aor = t1;
initial cl_idb_pcl = 0;
initial cl_idb_pch = 0;
always @* cl_idb_ir = uc.irl & t3;
always @* cl_ui_ir = uc.irl & t3;
always @* cl_ui_ie = (uc.drs == URS_IE);
always @* cl_db_idb = t3;
always @* cl_pc_inc = uc.irl & t2;
always @* cl_uc_final = (uc.fcy == tx);

endmodule
