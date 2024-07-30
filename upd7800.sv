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
   output        M1, // opcode fetch cycle
   output        RDB, // read
   output        WRB  // write
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

reg          resg;
reg          cp2;
reg [7:0]    v, a, b, c, d, e, h, l, w;
reg [7:0]    psw;
reg [15:0]   sp, pc;
reg [10:0]   ir;
reg          ie;                // interrupt enable flag
reg [15:0]   aor;
reg [7:0]    dor;
reg          rd_ext, wr_ext;
reg [7:0]    rfo, idb;
reg [15:0]   ab;
reg [7:0]    ai, bi, ibi, co;
reg          addc, notbi, pdah, pdal, pdac, cco, cho;
reg [15:0]   uabi, nabi;
reg          skso;

reg [3:0]    oft;
reg [2:0]    of_prefix;
wire         of_done;
reg          m1, m1ext;
wire         m1_next, oft0_next;
wire         m1_overlap, m1_skip;

s_ird        ird;

s_uc         uc;
e_uaddr      uptr, uptr_next;

reg          cl_idb_psw, cl_idbz_z, cl_cco_c, cl_zero_c, cl_one_c, cl_cho_hc;
reg          cl_sks_sk;
e_abs        cl_abs;
reg          cl_idb_pcl, cl_idb_pch, cl_pc_inc, cl_pc_dec;
reg          cl_abi_sp, cl_abi_pc;
reg          cl_idb_ir, cl_of_prefix_ir;
reg          cl_ui_ie;
reg          cl_abl_aor, cl_abh_aor, cl_ab_aor;
reg          cl_idb_dor, cl_store_dor;
reg          cl_load_db;
e_urfs       cl_rfts;
e_idbs       cl_idbs;
reg          cl_abi_inc, cl_abi_dec;
reg          cl_idb_abil, cl_idb_abih;
reg          cl_sums_cco, cl_carry, cl_one_addc, cl_c_addc, cl_zero_bi,
             cl_bi_not, cl_bi_dah, cl_bi_dal, cl_pdas;
reg          cl_clrs, cl_sums, cl_incs, cl_decs, cl_ors, cl_ands, cl_eors,
             cl_asls, cl_rols, cl_lsrs, cl_rors;


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
  resg = 1'b1;
end

assign resp = ~RESETB;

always_ff @(posedge CLK) begin
  if (cp2n) begin
    resg <= resp;
  end
end


//////////////////////////////////////////////////////////////////////
// External interface

initial begin
  rd_ext = 1'b1;
  wr_ext = 1'b1;
end

always_ff @(posedge CLK) begin
  if (resg) begin
    rd_ext <= 0;
    wr_ext <= 0;
  end
  else begin
    // RDB/WRB asserts in T2 @ CP1 rising, de-asserts in T3 @ CP2 falling
    if (cp1p) begin
      rd_ext <= rd_ext | cl_load_db;
      wr_ext <= wr_ext | cl_store_dor;
    end
    else if (cp2n) begin
      rd_ext <= rd_ext & cl_load_db;
      wr_ext <= wr_ext & cl_store_dor;
    end
  end
end

assign DB_O = dor;
assign DB_OE = ~WRB;
assign A = aor;
assign RDB = ~rd_ext;
assign WRB = ~wr_ext;

assign M1 = m1ext;


//////////////////////////////////////////////////////////////////////
// Registers

// General-purpose registers
always @(posedge CLK) begin
  if (cp2n) begin
    if (uc.lts == ULTS_RF) begin
      case (cl_rfts)
        URFS_V: v <= idb;
        URFS_A: a <= idb;
        URFS_B: b <= idb;
        URFS_C: c <= idb;
        URFS_D: d <= idb;
        URFS_E: e <= idb;
        URFS_H: h <= idb;
        URFS_L: l <= idb;
        default: ;
      endcase
    end
    if (uc.abits != UABS_PC) begin
      case (uc.abits)
        UABS_BC: {b, c} <= nabi;
        UABS_DE: {d, e} <= nabi;
        UABS_HL: {h, l} <= nabi;
        default: ;
      endcase
    end
  end
end

// Working register
always @(posedge CLK) begin
  if (cp2n) begin
    if ((uc.lts == ULTS_RF) & (uc.rfts == URFS_W)) begin
      w <= idb;
    end
  end
end

// psw: processor status word
always @(posedge CLK) begin
  if (resg) begin
    psw <= 0;
  end
  else if (cp2n) begin
    if (cl_idb_psw)
      psw <= idb;

    if (cl_idbz_z)
      `psw_z <= ~|idb;

    if (cl_cco_c)
      `psw_cy <= cco;
    if (cl_zero_c)
      `psw_cy <= 1'b0;
    if (cl_one_c)
      `psw_cy <= 1'b1;

    if (cl_cho_hc)
      `psw_hc <= cho;

    if (cl_sks_sk)
      `psw_sk <= skso;
  end
end

// sp: stack pointer
always @(posedge CLK) begin
  if (resg) begin
    sp <= 0;
  end
  else if (cp2p) begin
    if (uc.lts == ULTS_RF) begin
      case (cl_rfts)
        URFS_SPL: sp[7:0] <= idb;
        URFS_SPH: sp[15:8] <= idb;
        default: ;
      endcase
    end
    if (uc.abits == UABS_SP) begin
      sp <= nabi;
    end
  end
end

// pc: program ("P") counter
always @(posedge CLK) begin
  if (resg) begin
    pc <= 0;
  end
  else if (cp2p) begin
    if (cl_abi_pc) begin
      pc <= nabi;
    end
  end
end

assign pcl = pc[7:0];
assign pch = pc[15:8];

// ir: instruction (opcode) register
always @(posedge CLK) begin
  if (resg) begin
    ir <= 0;
  end
  if (cp2n) begin
    if (cl_idb_ir) begin
      ir[7:0] <= idb;
    end
    if (cl_of_prefix_ir) begin
      ir[10:8] <= of_prefix;
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
    if (cl_idb_dor) begin
      dor <= idb;
    end
  end
end


//////////////////////////////////////////////////////////////////////
// Internal buses

// rfo: register file output
always @* begin
  case (uc.rfos)
    URFS_V: rfo = v;
    URFS_A: rfo = a;
    URFS_B: rfo = b;
    URFS_C: rfo = c;
    URFS_D: rfo = d;
    URFS_E: rfo = e;
    URFS_H: rfo = h;
    URFS_L: rfo = l;
    URFS_PCL: rfo = pcl;
    URFS_PCH: rfo = pch;
    URFS_W: rfo = w;
    default: rfo = 8'hxx;
  endcase
end

// idb: internal data bus
always @* begin
  case (cl_idbs)
    UIDBS_0: idb = 0;
    UIDBS_RF: idb = rfo;
    UIDBS_DB: idb = DB_I;
    UIDBS_JRL: idb = {{3{ir[5]}}, ir[4:0]};
    UIDBS_JRH: idb = {8{ir[5]}};
    UIDBS_CO: idb = co;
    default: idb = 8'hxx;
  endcase
end

// ab: (internal) address bus
always @* begin
  case (cl_abs)
    UABS_PC: ab = pc;
    UABS_SP: ab = sp;
    UABS_BC: ab = {b, c};
    UABS_DE: ab = {d, e};
    UABS_HL: ab = {h, l};
    UABS_VW: ab = {v, w};
    UABS_IDB_W: ab = {idb, w};
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
  if (cl_zero_bi) begin
    bi <= 0;
  end
end

always @* addc = (cl_carry & cco) | (cl_one_addc | cl_incs) | (cl_c_addc & `psw_cy);
always @* notbi = cl_bi_not | cl_decs;
always @* pdah = (`psw_cy ^ cl_pdas) | (ai > 8'h99);
always @* pdal = (`psw_hc ^ cl_pdas) | (ai[3:0] > 4'h9);
always @* pdac = (~cl_pdas & (`psw_cy | pdah)) | (cl_pdas & `psw_cy & ~pdah);

always @* begin
  ibi = bi;
  if (cl_incs | cl_decs)
    ibi = 8'h00;
  // DAA/DAS adjust constants
  if (cl_bi_dah & pdah)
    ibi = 8'h60;
  if (cl_bi_dal & pdal)
    ibi = 8'h06;
  ibi = ibi ^ {8{notbi}};
end

// Maths
always @(posedge CLK) if (cp2n) begin
  if (cl_sums | cl_incs | cl_decs) begin :sums
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
// Address bus incrementer / decrementer

// update: change part or all
always @(posedge CLK) begin
  if (cp1p) begin
    uabi <= ab;

    if (cl_idb_abil)
      uabi[7:0] <= idb;
    if (cl_idb_abih)
      uabi[15:8] <= idb;
  end
end

// next: increment/decrement
always @* begin
  nabi = uabi;

  if (cl_abi_inc)
    nabi = nabi + 1;
  else if (cl_abi_dec)
    nabi = nabi - 1;
end


//////////////////////////////////////////////////////////////////////
// Skip flag source

always @* begin
  case (uc.pswsk)
    USKS_0: skso = 1'b0;
    USKS_1: skso = 1'b1;
    USKS_C: skso = cco;
    USKS_NC: skso = ~cco;
    USKS_Z: skso = ~|idb;
    USKS_NZ: skso = |idb;
    default: skso = 1'bx;
  endcase

  // A skipped instruction resets SK.
  if (m1_skip)
    skso = 1'b0;
end


//////////////////////////////////////////////////////////////////////
// Opcode fetch
//
// Instruction execution and opcode fetch can sometimes overlap.

always_ff @(posedge CLK) begin
  if (resg) begin
    oft[3:1] <= 0;
    m1ext <= 0;
  end
  else begin
    if (cp2n) begin
      oft[3:1] <= oft[2:0];
    end
    if (cp1p) begin
      m1ext <= m1 & |oft[2:0];
    end
  end
end

// M1 cycle should start as soon as resg clears.
always_ff @(posedge CLK) begin
  if (cp2n) begin
    oft[0] <= oft0_next;
    m1 <= m1_next;
  end
end  

assign oft0_next = (m1_next & ~|oft[2:0]) | (~resg & m1 & |of_prefix);
assign m1_overlap = of_done & ird.m1_overlap;
assign m1_skip = of_done & (`psw_sk & (ird.skipn == 0));
assign m1_next = (resg & ~resp) | (~resg & ((m1 & ~oft[3]) | (uc.m1 | m1_overlap | m1_skip)));

// Handle fetching a prefix opcode (1st of 2-byte opcode)
always @* begin
  of_prefix = 0;
  if (~|ir[10:8]) begin
    case (ir[7:0])
      8'h48: of_prefix = 3'd1;
      8'h4C: of_prefix = 3'd2;
      8'h4D: of_prefix = 3'd3;
      8'h60: of_prefix = 3'd4;
      8'h64: of_prefix = 3'd5;
      8'h70: of_prefix = 3'd6;
      default: ;
    endcase
  end
end

assign of_done = oft[3] & ~(m1 & |of_prefix);


//////////////////////////////////////////////////////////////////////
// Instruction decode

// Ugly hack to get the ball rolling...
s_ird ird_lut [2048];

initial begin
int i;
  // Illegal opcode default: fetch new opcode
  for (i = 0; i < 2048; i++) begin
    // default for illegal opcodes
    ird_lut[i] = { UA_IDLE, 1'd1, 2'd0 };
  end

`include "uc-ird.svh"
end

always @* ird = ird_lut[ir];


//////////////////////////////////////////////////////////////////////
// Microcode

s_uc    uram [256];

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

  if (of_done) begin
    if (`psw_sk) begin
      case (ird.skipn)
        2'd0: uptr_next = UA_IDLE;
        2'd1: uptr_next = UA_SKIP_OP1_T1;
        2'd2: uptr_next = UA_SKIP_OP2_T1;
        default: ;
      endcase
    end
    else begin
      uptr_next = ird.addr;
    end
  end
  else begin
    case (uc.bm)
      UBM_ADV: uptr_next = e_uaddr'(uptr_next + 1'd1);
      UBM_END: uptr_next = UA_IDLE;
      UBM_DA: uptr_next = uc.nua;
      default: ;
    endcase
  end
end

always_ff @(posedge CLK) begin
  if (resg) begin
    uptr <= UA_IDLE;
  end
  else if (cp2p) begin
    uptr <= uptr_next;
  end
end


//////////////////////////////////////////////////////////////////////
// Control logic

initial cl_idb_psw = 0;
initial cl_idbz_z = uc.pswz;
always @* cl_cco_c = uc.pswcy;
initial cl_zero_c = 0;
initial cl_one_c = 0;
always @* cl_cho_hc = uc.pswhc;
always @* cl_sks_sk = (uc.bm == UBM_END) | m1_skip;
initial cl_abl_aor = 0;
initial cl_abh_aor = 0;
always @* cl_ab_aor = oft[0] | uc.aout;
always @* cl_idb_dor = (uc.lts == ULTS_DOR);
always @* cl_store_dor = uc.store;
always @* cl_load_db = oft[1] | uc.load;
always @* cl_idbs = e_idbs'(oft[2] ? UIDBS_DB : uc.idbs);
always @* cl_idb_pcl = (uc.lts == ULTS_RF) & (uc.rfts == URFS_PCL);
always @* cl_idb_pch = (uc.lts == ULTS_RF) & (uc.rfts == URFS_PCH);
always @* cl_pc_inc = uc.pc_inc;
always @* cl_pc_dec = (uc.abs == UABS_PC) & cl_abi_dec;
always @* cl_abi_pc = oft[3] | cl_idb_pcl | cl_idb_pch | cl_pc_inc | cl_pc_dec;
always @* cl_idb_ir = oft[2];
always @* cl_of_prefix_ir = oft[2];
always @* cl_ui_ie = uc.lts == ULTS_IE;
always @* cl_abs = e_abs'(oft[0] ? UABS_PC : uc.abs);
always @* cl_idb_abil = cl_idb_pcl;
always @* cl_idb_abih = cl_idb_pch;
always @* cl_abi_inc = oft[3] | cl_pc_inc | uc.ab_inc;
always @* cl_abi_dec = uc.ab_dec;
initial cl_sums_cco = 1'b1;
always @* cl_carry = uc.cis == UCIS_CCO;
always @* cl_one_addc = uc.cis == UCIS_1;
always @* cl_c_addc = uc.cis == UCIS_PSW_CY;
always @* cl_zero_bi = uc.bi0;
always @* cl_bi_not = uc.bin;
initial cl_bi_dah = 0;
initial cl_bi_dal = 0;
initial cl_pdas = 0;
initial cl_clrs = 0;
always @* cl_sums = uc.aluop == UAO_SUM;
always @* cl_incs = uc.aluop == UAO_INC;
always @* cl_decs = uc.aluop == UAO_DEC;
initial cl_ors = 0;
initial cl_ands = 0;
initial cl_eors = 0;
initial cl_asls = 0;
initial cl_rols = 0;
initial cl_lsrs = 0;
initial cl_rors = 0;

always @* begin
  cl_rfts = uc.rfts;
  if (uc.rfts == URFS_IR210) begin
    // IR[2:0] encodes V,A,B...L
    cl_rfts = e_urfs'({2'b00, ir[2:0]});
  end
end


endmodule
