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

wire         resp;
wire         cp1p, cp2p, cp2n;
wire         t0;                // next machine cycle
wire [15:0]  pcl, pch;
wire [7:0]   db;
wire [2:0]   ui;

reg          resg;
reg          cp2;
reg          t1, t2, t3, t4;    // machine cycle (step)
reg [15:0]   pc;
reg [15:0]   ab;
reg [15:0]   aor;
reg [7:0]    idb;
reg [7:0]    dor;
reg [10:0]   ir;

reg          cl_db_idb;
reg          cl_idb_ir, cl_ui_ir;
reg          cl_abl_aor, cl_abh_aor, cl_ab_aor;

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
  else if (cp1p) begin
    t1 <= t0;
    t2 <= t1;
    t3 <= t2;
    t4 <= t3 & ~t0;
  end
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

// pc: program ("P") counter
always @(posedge CLK) begin
  if (resg) begin
    pc <= 0;
  end
  else if (cp2p) begin
    //pc <= npc;
  end
end

assign pcl = pc[7:0];
assign pch = pc[15:8];

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

// ir: instruction register
always @(posedge CLK) begin
  if (cp2n) begin
    if (cl_idb_ir) begin
      ir[7:0] <= idb;
    end
    if (cl_ui_ir) begin
      ir[10:8] <= ui[2:0];
    end
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

typedef enum reg [1:0]
{
 UBM_DA,
 UBM_AT
} e_ubm;                        // branch mode

typedef enum reg [6:0]
{
 UA_FETCH_IR1,
 UA_OP48_FETCH_IR2,
 UA_DI,
 UA_UNDEF // just a placeholder
} e_uaddr;                      // microcode address

typedef struct packed
{
  reg [2:0] idx;                // index
  reg irl;                      // ir load
  e_ubm bm;                     // branch mode
  e_uaddr nua;                  // next address
} s_uc;

s_uc    uram [64];
s_uc    uc;
e_uaddr uptr, uptr_next;
e_uaddr at;

initial begin
  uram[UA_FETCH_IR1] = { 3'd0, 1'b1, UBM_AT, UA_UNDEF };
  uram[UA_OP48_FETCH_IR2] = { 3'd1, 1'b1, UBM_AT, UA_UNDEF };
end

always_ff @(posedge CLK) begin
  uc <= uram[uptr];
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
  else if (cp1p & t4) begin
    uptr <= uptr_next;
  end
end

assign ui = uc.idx;


//////////////////////////////////////////////////////////////////////
// Microcode address generator

// Ugly hack to get the ball rolling...
e_uaddr at_lut [2048];

initial begin
int i;
  // Illegal opcode default: fetch new opcode
  for (i = 0; i < 2048; i++)
    at_lut[i] = UA_FETCH_IR1;

  at_lut['h048] = UA_OP48_FETCH_IR2;

  at_lut['h124] = UA_DI;
end

// redundant typecast makes iverilog happy
always @* at = e_uaddr'(at_lut[ir]);


//////////////////////////////////////////////////////////////////////
// Control logic

initial cl_abl_aor = 0;
initial cl_abh_aor = 0;
always @* cl_ab_aor = t0;
always @* cl_idb_ir = uc.irl & t3;
always @* cl_ui_ir = uc.irl & t3;
always @* cl_db_idb = t3;

endmodule
