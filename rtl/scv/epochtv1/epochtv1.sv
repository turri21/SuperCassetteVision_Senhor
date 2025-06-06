// Epoch TV-1 - a trivial implementation
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

// References:
// . https://github.com/mamedev/mame - src/mame/epoch/scv.cpp
// . https://forums.atariage.com/topic/130365-atari-7800-vs-epoch-super-cassette-vision/ - [takeda.txt]
// . http://takeda-toshiya.my.coocan.jp/scv/index.html
// . https://upsilandre.over-blog.com/2022/10/sprite-hardware-80-s-le-grand-comparatif.html


`timescale 1us / 1ns

import scv_pkg::*;

module epochtv1
  (
   input         CLK, // clock (XTAL * 2)
   input         CE, // pixel clock enable

   // ROM initialization
   input         ROMINIT_SEL_CHR,
   input [9:0]   ROMINIT_ADDR,
   input [7:0]   ROMINIT_DATA,
   input         ROMINIT_VALID,

   // Emulator configuration
   input         palette_t CFG_PALETTE,

   // CPU address / data bus
   input         CP1_POSEDGE, // for CPU bus timing
   input [12:0]  A,
   input [7:0]   DB_I,
   output [7:0]  DB_O,
   output        DB_OE,
   input         RDB,
   input         WRB,
   input         CSB,
   output        WAITB,
   output        SCPUB, // uPD1771C chip select

   // VRAM address / data bus A, low byte
   output [11:0] VAA,
   input [7:0]   VAD_I,
   output [7:0]  VAD_O,
   output        nVARD,
   output        nVAWR,

   // VRAM address / data bus B, high byte
   output [11:0] VBA,
   input [7:0]   VBD_I,
   output [7:0]  VBD_O,
   output        nVBRD,
   output        nVBWR,

   // video output
   output        VBL,
   output        DE,
   output        HS,
   output        VS,
   output [23:0] RGB // {R,G,B}
   );


// Timing acquired by measuring actual hardware.
localparam [8:0] NUM_ROWS = 9'd263;
localparam [8:0] NUM_COLS = 9'd260;

// Actual render window (incl. overscan): 208 x 232
localparam [8:0] FIRST_ROW_RENDER = 9'd16;
localparam [8:0] LAST_ROW_RENDER = 9'd247;
localparam [8:0] FIRST_COL_RENDER = 9'd23;
localparam [8:0] LAST_COL_RENDER = 9'd230;
localparam [8:0] FIRST_ROW_VSYNC = 9'd257;
localparam [8:0] LAST_ROW_VSYNC = 9'd259;
localparam [8:0] FIRST_COL_HSYNC = 9'd240;
localparam [8:0] LAST_COL_HSYNC = 9'd259;

localparam [8:0] FIRST_ROW_PRE_RENDER = FIRST_ROW_RENDER - 'd2;
localparam [8:0] FIRST_ROW_BOC_START = LAST_ROW_RENDER + 'd2;

// Visible window: 204 x 230 = (1,2)-(204,231)
//
// Hide render window edges, which would normally be hidden by
// overscan.
localparam [8:0] FIRST_ROW_VISIBLE = FIRST_ROW_RENDER + 'd2;
localparam [8:0] LAST_ROW_VISIBLE = LAST_ROW_RENDER;
localparam [8:0] FIRST_COL_VISIBLE = FIRST_COL_RENDER + 'd1;
localparam [8:0] LAST_COL_VISIBLE = LAST_COL_RENDER - 'd3;

`ifdef EPOCHTV1_BORDERS
// left/right borders
localparam [8:0] FIRST_COL_LEFT = FIRST_COL_VISIBLE - 1'd8;
localparam [8:0] LAST_COL_LEFT = FIRST_COL_VISIBLE - 1'd1;
localparam [8:0] FIRST_COL_RIGHT = LAST_COL_VISIBLE + 1'd1;
localparam [8:0] LAST_COL_RIGHT = LAST_COL_VISIBLE + 1'd8;
`endif


reg [8:0]    row, col;
reg          field;
wire         pre_render_row;
wire         render_row, render_col, render_px;
wire         visible_row, visible_col, visible_px;
wire         cpu_sel_bgm, cpu_sel_oam, cpu_sel_vram, cpu_sel_reg, cpu_sel_apu;
wire         cpu_rd, cpu_wr, cpu_rdwr;
wire         sbofp_stall;
reg [5:0]    sbofp_bgr_idx;

//////////////////////////////////////////////////////////////////////
// MMIO registers ($1400-$1403)

reg [7:0]    ioreg0, ioreg1, ioreg2, ioreg3;
reg [7:0]    ioreg_do;

initial begin
  ioreg0 = 0;
  ioreg1 = 0;
  ioreg2 = 0;
  ioreg3 = 0;
end

always @(posedge CLK) begin
  if (cpu_sel_reg & cpu_wr) begin
    case (A[1:0])
      2'd0: ioreg0 <= DB_I;
      2'd1: ioreg1 <= DB_I;
      2'd2: ioreg2 <= DB_I;
      2'd3: ioreg3 <= DB_I;
    endcase
  end
end

always @* begin
  ioreg_do = 8'hxx;
  case (A[1:0])
    2'd0: ioreg_do = ioreg0;
    2'd1: ioreg_do = ioreg1;
    2'd2: ioreg_do = ioreg2;
    2'd3: ioreg_do = ioreg3;
    default: ;
  endcase
end

// Handy aliases

wire         bm_ena = ioreg0[0];   // enable bitmap
wire         bm_lores = ioreg0[1]; // bitmap res: 0=lo, 1=hi
wire         sp_hide7 = ioreg0[2]; // hide sprites 64-127
wire         sp_ena = ioreg0[4];   // enable sprites
wire         sp_2clrm = ioreg0[5]; // 2-color sprite mode
wire         bm_invx = ioreg0[6];  // invert XMAX effect
wire         bm_invy = ioreg0[7];  // invert YMAX effect

// Bitmap FG/BG colors
wire [3:0]   bm_clr_bg = ioreg1[3:0];
wire [3:0]   bm_clr_fg = ioreg1[7:4]; // high-resolution mode only

// Character / graphics window split
wire [3:0]   bm_xmax = ioreg2[3:0];
wire [3:0]   bm_ymax = ioreg2[7:4];

// Character FG/BG colors
wire [3:0]   ch_clr_bg = ioreg3[3:0];
wire [3:0]   ch_clr_fg = ioreg3[7:4];


//////////////////////////////////////////////////////////////////////
// Video counter

initial begin
  row = 0;
  col = 0;
  field = 0;
end

always_ff @(posedge CLK) if (CE) begin
  if (col == NUM_COLS - 1'd1) begin
    col <= 0;
    if (row == NUM_ROWS - 1'd1) begin
      row <= 0;
      field <= ~field;
    end
    else begin
      row <= row + 1'd1;
    end
  end
  else begin
    col <= col + 1'd1;
  end
end


//////////////////////////////////////////////////////////////////////
// Character pattern ROM (CHR)

reg [7:0] chr [1024];

wire [9:0] chr_a;
reg [7:0]  chr_rbuf;

always_ff @(posedge CLK) begin
  if (ROMINIT_SEL_CHR & ROMINIT_VALID) begin
    chr[ROMINIT_ADDR] <= ROMINIT_DATA;
  end
end

always_ff @(posedge CLK) begin
  chr_rbuf <= chr[chr_a];
end


//////////////////////////////////////////////////////////////////////
// Background memory (BGM)

reg [31:0] bgm [128];

wire [6:0] bgm_a;
wire       bgm_a_sel_cpu;
wire [6:0] bgm_ra;
reg [31:0] bgm_rbuf;
wire [3:0] bgm_we;
wire [31:0] bgm_wbuf;

assign bgm_a = bgm_a_sel_cpu ? A[8:2] : bgm_ra;
assign bgm_wbuf = {4{DB_I}};
assign bgm_we = {3'b0, (cpu_sel_bgm & cpu_wr)} << A[1:0];

always_ff @(posedge CLK) begin
  bgm_rbuf <= bgm[bgm_a];
  for (int i = 0; i < 4; i++) begin
    if (bgm_we[i]) begin
      bgm[bgm_a][(i*8)+:8] <= bgm_wbuf[(i*8)+:8];
    end
  end
end


//////////////////////////////////////////////////////////////////////
// Background memory copy (BGM2)

reg [31:0] bgm2 [128];

wire [6:0] bgm2_ra;
reg [31:0] bgm2_rbuf;
wire [6:0] bgm2_wa;
wire       bgm2_we;
wire [31:0] bgm2_wbuf;

always_ff @(posedge CLK) begin
  bgm2_rbuf <= bgm2[bgm2_ra];
  if (bgm2_we) begin
    bgm2[bgm2_wa] <= bgm2_wbuf;
  end
end


//////////////////////////////////////////////////////////////////////
// Sprite attribute memory (OAM)

reg [31:0] oam [128];

wire [6:0] oam_a;
wire       oam_a_sel_cpu;
wire [6:0] oam_ra;
reg [31:0] oam_rbuf;
wire [3:0] oam_we;
wire [31:0] oam_wbuf;

assign oam_a = oam_a_sel_cpu ? A[8:2] : oam_ra;
assign oam_wbuf = {4{DB_I}};
assign oam_we = {3'b0, (cpu_sel_oam & cpu_wr)} << A[1:0];

always_ff @(posedge CLK) begin
  oam_rbuf <= oam[oam_a];
  for (int i = 0; i < 4; i++) begin
    if (oam_we[i]) begin
      oam[oam_a][(i*8)+:8] <= oam_wbuf[(i*8)+:8];
    end
  end
end


//////////////////////////////////////////////////////////////////////
// Sprite attribute memory copy (OAM2)

reg [31:0] oam2 [128];

wire [6:0] oam2_ra;
reg [31:0] oam2_rbuf;
wire [6:0] oam2_wa;
wire       oam2_we;
wire [31:0] oam2_wbuf;

always_ff @(posedge CLK) begin
  oam2_rbuf <= oam2[oam2_ra];
  if (oam2_we) begin
    oam2[oam2_wa] <= oam2_wbuf;
  end
end


//////////////////////////////////////////////////////////////////////
// BGM / OAM copier
//
// Copies each memory into its respective memory copy. Copy starts in
// VBL, runs to completion, and stalls on CPU access to memory.

reg [6:0] boc_idx;
reg       boc_active;
wire      boc_stall, boc_stall_pre;
reg       boc_stall_d;
wire      boc_we;

initial begin
  boc_active = 0;
end

// boc_stall deassertion needs to lag cpu_rdwr deassertion by 1x CE,
// to give memories a chance to recover.
assign boc_stall_pre = (cpu_sel_bgm | cpu_sel_oam) & cpu_rdwr;
always_ff @(posedge CLK) if (CE) begin
  boc_stall_d <= boc_stall_pre;
end
assign boc_stall = boc_stall_pre | boc_stall_d;

always_ff @(posedge CLK) if (CE) begin
  if (~boc_active) begin
    if ((row == FIRST_ROW_BOC_START) & (col == 0)) begin
      boc_active <= '1;
      boc_idx <= 0;
    end
  end
  else if (~boc_stall) begin
    if (boc_idx == '1) begin
      boc_active <= 0;
    end
    else begin
      boc_idx <= boc_idx + 1'd1;
    end
  end
end

assign boc_we = CE & boc_active & ~boc_stall;

assign bgm_ra = boc_idx;
assign bgm2_wbuf = bgm_rbuf;
assign bgm2_wa = boc_idx;
assign bgm2_we = boc_we;

assign oam_ra = boc_idx;
assign oam2_wbuf = oam_rbuf;
assign oam2_wa = boc_idx;
assign oam2_we = boc_we;


//////////////////////////////////////////////////////////////////////
// CPU address / data bus interface

reg [7:0] cpu_do;
reg       cpu_csb_d;
reg       cpu_waitb_p;

// Address decoder
assign cpu_sel_vram = ~CSB & (A[12] == 1'b0);     // $0000 - $0FFF
assign cpu_sel_bgm = ~CSB & (A[12:9] == 4'b1000); // $1000 - $11FF
assign cpu_sel_oam = ~CSB & (A[12:9] == 4'b1001); // $1200 - $13FF
assign cpu_sel_reg = ~CSB & (A[12:9] == 4'b1010); // $1400 - $15FF
assign cpu_sel_apu = ~CSB & (A[12:9] == 4'b1011); // $1600 - $17FF

assign cpu_rd = ~(CSB | RDB);
assign cpu_wr = ~(CSB | WRB);
assign cpu_rdwr = cpu_rd | cpu_wr;

always @(posedge CLK) if (CP1_POSEDGE) begin
  cpu_csb_d <= CSB;
  cpu_waitb_p <= CSB | cpu_rdwr;
end
wire cpu_csb_negedge = ~CSB & cpu_csb_d;

always_ff @(posedge CLK) if (CE) begin
  if (cpu_rd) begin
    if (cpu_sel_vram)
      cpu_do <= A[0] ? VBD_I : VAD_I;
    else if (cpu_sel_bgm)
      cpu_do <= bgm_rbuf[(A[1:0]*8)+:8];
    else if (cpu_sel_oam)
      cpu_do <= oam_rbuf[(A[1:0]*8)+:8];
    else if (cpu_sel_reg)
      cpu_do <= ioreg_do;
  end
end

assign DB_O = DB_OE ? cpu_do : 8'hzz;
assign DB_OE = cpu_rd;
assign SCPUB = ~cpu_sel_apu;
assign WAITB = ~cpu_csb_negedge & cpu_waitb_p;

assign bgm_a_sel_cpu = cpu_sel_bgm & cpu_rdwr;
assign oam_a_sel_cpu = cpu_sel_oam & cpu_rdwr;


//////////////////////////////////////////////////////////////////////
// VRAM address / data bus interface

reg [11:0] va;
reg [11:0] spr_vram_addr;

assign va = (cpu_sel_vram & cpu_rdwr) ? A[12:1] : spr_vram_addr;

assign VAA = va;
assign VAD_O = DB_I;
assign nVARD = 1'b0;
assign nVAWR = ~(cpu_sel_vram & cpu_wr & ~A[0]);
assign VBA = va;
assign VBD_O = DB_I;
assign nVBRD = 1'b0;
assign nVBWR = ~(cpu_sel_vram & cpu_wr & A[0]);



//////////////////////////////////////////////////////////////////////
// Background (character / bitmap) pipeline

wire [8:0] bgr_row;
wire [4:0] bgr_tx;
wire [4:0] bgr_ty;
wire       bgr_tx_valid;
wire       bgr_xwin, bgr_ywin;
wire       bgr_bm;
wire       bgr_ch;
wire [7:0] bgr_bgm_rd;

wire [3:0] bgr_ch_bgc, bgr_ch_fgc;
reg [7:0]  bgr_ch_pat;

reg [3:0]  bgr_bm_bgc, bgr_bm_fgc;
reg [7:0]  bgr_bm_pat;

reg [3:0]  bgr_bgc, bgr_fgc;
reg [7:0]  bgr_pxp, bgr_px;
reg [4:0]  bgr_wa;
reg [7:0]  bgr_we;

assign bgr_row = row + 1; // +1 aligns BG w/ render window top

assign bgr_tx = sbofp_bgr_idx[4:0];
assign bgr_ty = bgr_row[7:3];
assign bgr_tx_valid = ~sbofp_bgr_idx[5];

assign bgr_xwin = (bgr_tx[4:1] < bm_xmax) ^ bm_invx;
assign bgr_ywin = (bgr_ty[4:1] < bm_ymax) ^ bm_invy;

assign bgr_bm = bm_ena & ~bgr_ch;
assign bgr_ch = bgr_xwin & bgr_ywin;

// Read data from BGM
assign bgm2_ra = {bgr_ty[4:1], bgr_tx[4:2]};
assign bgr_bgm_rd = bgm2_rbuf[(bgr_tx[1:0]*8)+:8];

// Read character pattern from ROM
assign chr_a = {bgr_bgm_rd[6:0], bgr_row[2:0]};
assign bgr_ch_bgc = ch_clr_bg;
assign bgr_ch_fgc = ch_clr_fg;
assign bgr_ch_pat = bgr_ty[0] ? 0 : chr_rbuf;

// Interpret BGM data as bitmap data
wire [2:0] bgr_bm_hipat_sel = {~bgr_row[3:2], 1'b0};
wire [2:0] bgr_bm_lopat_sel = {~bgr_row[3], 2'b0};
wire [1:0] bgr_bm_hipat = bgr_bgm_rd[bgr_bm_hipat_sel+:2];
wire [3:0] bgr_bm_lopat = bgr_bgm_rd[bgr_bm_lopat_sel+:4];

always @* begin
  bgr_bm_bgc = bm_clr_bg;
  bgr_bm_fgc = bm_clr_fg;
  bgr_bm_pat = 0;
  if (bgr_bm) begin
    if (bm_lores) begin
      if (bgr_bm_lopat != 4'd0) begin // 0 is transparent
        bgr_bm_pat = '1;
        bgr_bm_fgc = bgr_bm_lopat;
      end
    end
    else
      bgr_bm_pat = {{4{bgr_bm_hipat[1]}}, {4{bgr_bm_hipat[0]}}};
  end
end

// Background patterns are reversed
always @* begin
  for (int i = 0; i < 8; i++)
    bgr_pxp[7-i] = bgr_ch ? bgr_ch_pat[i] : bgr_bm_pat[i];
end

always @(posedge CLK) if (CE) begin
  bgr_bgc <= bgr_ch ? bgr_ch_bgc : bgr_bm_bgc;
  bgr_fgc <= bgr_ch ? bgr_ch_fgc : bgr_bm_fgc;
  bgr_px <= bgr_pxp;
  bgr_wa <= bgr_tx;
  bgr_we <= {8{bgr_tx_valid}};
end


//////////////////////////////////////////////////////////////////////
// Sprite pipeline

typedef struct packed
{
    reg         split;
    reg [6:0]   tile;
    reg [6:0]   x;
    reg         link_x;
    reg [3:0]   start_line;
    reg [3:0]   color;
    reg [6:0]   y;
    reg         link_y;
} s_objattr;

reg [6:0]   spr_tile;
wire [15:0] spr_pat;
reg [6:0]   oam_idx;
s_objattr   spr_oa;
reg [8:0]   spr_y0;
wire        spr_half_w, spr_half_h;
wire        spr_dbl_w, spr_dbl_h;
reg [4:0]   spr_y, spr_w, spr_h;
wire [4:0]  spr_vs;             // top clip bounds
wire        spr_2clr;           // 2-color sprite (if link_x/y)
wire        spr_2halves;        // double-wide or 2-color (actual)
reg [3:0]   spr_color;
wire        spr_y_in_range;
wire        spr_visible;

wire        spr_d0;             // drawing start
wire        spr_dw2;            // drawing 2nd half of double-wide or 2-color
wire        spr_dh2;            // drawing bottom half of double-high
wire        spr_skip_dl, spr_skip_dr; // skip drawing left/right half
wire        spr_skip_dt, spr_skip_db; // skip drawing top/bottom half
wire        spr_skip_2clr;            // skip drawing 2nd half of 2-color
wire        spr_dl, spr_dr;     // drawing left/right half (of 16-px pat.)
reg [7:0]   spr_olb_we;

reg         spr_dact;
reg [7:0]   spr_dpat;
reg         spr_dact_d, spr_dact_d2;
reg [15:0]  spr_dsr;            // draw shift register
reg [7:0]   spr_dsx;            // current drawing column
reg [3:0]   spr_dclr;           // current sprite color

assign spr_pat = {VBD_I, VAD_I};
assign oam2_ra = oam_idx;
assign spr_oa = oam2_rbuf;

assign spr_vs = spr_oa.start_line*2;
assign spr_half_w = spr_oa.split;
assign spr_half_h = spr_oa.split & spr_oa.tile[6];
assign spr_dbl_w = ~(spr_half_w | spr_2clr) & spr_oa.link_x;
assign spr_dbl_h = ~(spr_half_h | spr_2clr) & spr_oa.link_y;
assign spr_2clr = sp_2clrm & oam_idx[5];
assign spr_2halves = spr_dbl_w | (spr_2clr & ~spr_skip_2clr);

assign spr_vram_addr = {1'b0, spr_tile, spr_y[3:1], spr_dr};

assign spr_w = spr_half_w ? 5'd7 : spr_dbl_w ? 5'd31 : 5'd15;
assign spr_h = spr_half_h ? 5'd7 : spr_dbl_h ? 5'd31 : 5'd15;
assign spr_y0 = spr_oa.y*2 + 1; // +1 aligns sprites w/ BG
assign spr_y_in_range = row >= spr_y0 + 9'(spr_vs) &&
                        row <= spr_y0 + 9'(spr_h);
assign spr_visible = |spr_oa.color & |spr_oa.y & spr_y_in_range;

assign spr_skip_dl = spr_half_w & spr_oa.link_x;
assign spr_skip_dr = spr_half_w & ~spr_oa.link_x;
assign spr_skip_dt = spr_half_h & spr_oa.link_y;
assign spr_skip_db = spr_half_h & ~spr_oa.link_y;
assign spr_skip_2clr = spr_2clr & ~(spr_oa.link_x | spr_oa.link_y);

always @* begin
  spr_tile = spr_oa.tile;
  if (spr_2clr & spr_dw2)
    spr_tile = spr_tile ^ {3'b0, spr_oa.link_x, 2'b0, spr_oa.link_y};
  else if (~spr_2clr)
    spr_tile = spr_tile | {3'b0, spr_dw2, 2'b0, spr_dh2};
end

reg [7:0] spr_2clr_lut [16];
initial begin
  spr_2clr_lut[ 0] = {4'd0,  4'd0 };
  spr_2clr_lut[ 1] = {4'd1,  4'd15};
  spr_2clr_lut[ 2] = {4'd8,  4'd12};
  spr_2clr_lut[ 3] = {4'd11, 4'd13};
  spr_2clr_lut[ 4] = {4'd2,  4'd10};
  spr_2clr_lut[ 5] = {4'd3,  4'd11};
  spr_2clr_lut[ 6] = {4'd10, 4'd8 };
  spr_2clr_lut[ 7] = {4'd9,  4'd9 };
  spr_2clr_lut[ 8] = {4'd4,  4'd6 };
  spr_2clr_lut[ 9] = {4'd5,  4'd7 };
  spr_2clr_lut[10] = {4'd12, 4'd4 };
  spr_2clr_lut[11] = {4'd13, 4'd5 };
  spr_2clr_lut[12] = {4'd6,  4'd2 };
  spr_2clr_lut[13] = {4'd7,  4'd3 };
  spr_2clr_lut[14] = {4'd14, 4'd1 };
  spr_2clr_lut[15] = {4'd15, 4'd1 };
end
wire [7:0] spr_2clr_lut_out = spr_2clr_lut[spr_oa.color];

always @* begin
  spr_color = spr_oa.color;
  if (spr_2clr & spr_dw2)
    spr_color = spr_2clr_lut_out[(oam_idx[6]*4)+:4];
end

always @* begin
  spr_y = 5'(row - spr_y0);
  if (spr_skip_dt)
    spr_y -= 5'd8;
end
assign spr_dh2 = spr_y_in_range & spr_dbl_h & spr_y[4];

always @* begin
  spr_dpat = 0;
  spr_dact = 0;
  if (spr_dl | spr_dr) begin
    spr_dact = 1'b1;
    for (int i = 0; i < 8; i++) begin
      spr_dpat[i] = spr_pat[4'd15 - {~i[2], spr_y[0], i[1:0]}];
    end
  end
end

always_ff @(posedge CLK) if (CE) begin
  if (~sbofp_stall) begin
    spr_dsr <= {spr_dpat, spr_dsr[15:8]};

    spr_dact_d <= spr_dact;
    if (spr_d0) begin
      spr_dsx <= spr_oa.x*2 - 6; // -6 aligns sprites w/ background
      spr_dclr <= spr_color;
    end
    else if (spr_dact_d) begin
      spr_dsx <= spr_dsx + 8'd8;
    end

    spr_dact_d2 <= spr_dact_d;
  end
end

function is_dsr_set(reg [15:0] dsr, int off, reg [2:0] x0);
reg [4:0] p;
  begin
    p = 5'd8 + off[4:0] - 5'(x0);
    is_dsr_set = dsr[4'(p)];
  end
endfunction

always @* begin
  spr_olb_we = 0;
  if (spr_dact_d | spr_dact_d2) begin
    for (int i = 0; i < 8; i++) begin
      spr_olb_we[i[2:0]] = is_dsr_set(spr_dsr, i, spr_dsx[2:0]);
    end
  end
end


//////////////////////////////////////////////////////////////////////
// Object Line Buffer (OLB)
// - 8 pixels wide to enable writing tile (1/2 sprite) in one cycle
// - pixel = 4 bit color
// - two full rows, used in ping-pong fashion

reg [5:0]   olb_wa;
reg [31:0]  olb_wd;
reg [7:0]   olb_we;
wire [5:0]  olb_ra;
reg [31:0]  olb_rd;
wire        olb_re;
genvar      olb_gi;

reg [31:0]  olb_rbuf [2];

// Declare one array per row. Each array should infer a simple
// dual-port RAM.
generate
  for (olb_gi = 0; olb_gi < 2; olb_gi++) begin :olb_row

  reg [31:0] mem [32];
  reg [4:0]  addr;
  reg [31:0] wbuf;
  reg [7:0]  we;

    always_ff @(posedge CLK) begin
      olb_rbuf[olb_gi] <= mem[addr];
      for (int i = 0; i < 8; i++) begin
        if (we[i]) begin
          mem[addr][(i*4)+:4] <= wbuf[(i*4)+:4];
        end
      end
    end

    always @* begin
      if (olb_wa[5] == olb_gi[0]) begin
        // This row is being written to.
        addr = olb_wa[4:0];
        wbuf = olb_wd;
        we = olb_we;
      end
      else /*if (olb_ra[5] == olb_gi[0])*/ begin
        // This row is being read from.
        addr = olb_ra[4:0];
        wbuf = 0;
        we = 0;
      end
    end
  end
endgenerate

always_ff @(posedge CLK) if (CE) begin
  if (olb_re) begin
    olb_rd <= olb_rbuf[olb_ra[5]]; // select read row
  end
end


//////////////////////////////////////////////////////////////////////
// Sprite / background OLB fill pipeline

typedef enum reg [2:0]
{
 SST_IDLE,
 SST_BG,
 SST_EVAL,
 SST_DRAW_L,
 SST_DRAW_R,
 SST_2CLR_FLUSH,
 SST_DRAW_L2,
 SST_DRAW_R2
} e_sbofp_st;

e_sbofp_st sbofp_st;

wire sbofp_stall_pre;
reg  sbofp_stall_d;

wire [6:0] sbofp_oam_idx_max;

wire sbofp_wsel;

reg [3:0]  sbofp_wdc_bg, sbofp_wdc_fg;
reg [7:0]  sbofp_wds;

// sbofp_stall deassertion needs to lag cpu_rdwr deassertion by 1x CE,
// to give memories a chance to recover.
assign sbofp_stall_pre = cpu_sel_vram & cpu_rdwr;
always_ff @(posedge CLK) if (CE) begin
  sbofp_stall_d <= sbofp_stall_pre;
end
assign sbofp_stall = sbofp_stall_pre | sbofp_stall_d;

assign sbofp_oam_idx_max = sp_hide7 ? 7'd63 : 7'd127;

initial begin
  sbofp_st = SST_IDLE;
  sbofp_bgr_idx = 6'd32;
  oam_idx = 0;
end

always_ff @(posedge CLK) if (CE) begin
  if (~(pre_render_row | render_row)) begin
    sbofp_st <= SST_IDLE;
  end
  else if (col == 0) begin
    sbofp_st <= SST_BG;
    sbofp_bgr_idx <= 0;
  end
  else if (~sbofp_stall) begin
    if (sbofp_st == SST_BG) begin
      if (sbofp_bgr_idx == 6'd32) begin // +1 for pipeline delay
        oam_idx <= 0;
        sbofp_st <= e_sbofp_st'(sp_ena ? SST_EVAL : SST_IDLE);
      end
      sbofp_bgr_idx <= sbofp_bgr_idx + 1'd1;
    end
    else if (sbofp_st == SST_EVAL) begin
      if (spr_visible) begin
        sbofp_st <= e_sbofp_st'(spr_skip_dl ? SST_DRAW_R : SST_DRAW_L);
      end
      else begin
        sbofp_st <= e_sbofp_st'((oam_idx < sbofp_oam_idx_max) ? SST_EVAL : SST_IDLE);
        oam_idx <= oam_idx + 1'd1;
      end
    end
    else if ((sbofp_st == SST_DRAW_L) & ~spr_skip_dr) begin
      sbofp_st <= SST_DRAW_R;
    end
    else if (((sbofp_st == SST_DRAW_L) | (sbofp_st == SST_DRAW_R)) &
             spr_2clr & ~spr_skip_2clr) begin
      sbofp_st <= SST_2CLR_FLUSH;
    end
    else if (((sbofp_st == SST_DRAW_L) | (sbofp_st == SST_DRAW_R) |
              (sbofp_st == SST_2CLR_FLUSH)) &
             spr_2halves & ~spr_skip_dl) begin
      sbofp_st <= SST_DRAW_L2;
    end
    else if (((sbofp_st == SST_DRAW_R) | (sbofp_st == SST_DRAW_L2)) &
             spr_2halves & ~spr_skip_dr) begin
      sbofp_st <= SST_DRAW_R2;
    end
    else if (spr_dl | spr_dr) begin
      sbofp_st <= e_sbofp_st'((oam_idx < 7'd127) ? SST_EVAL : SST_IDLE);
      oam_idx <= oam_idx + 1'd1;
    end
  end
end

assign spr_d0 = (~spr_dw2 | spr_2clr) & (spr_dl | (spr_dr & spr_skip_dl));
assign spr_dw2 = (sbofp_st == SST_DRAW_L2) | (sbofp_st == SST_DRAW_R2);
assign spr_dl = (sbofp_st == SST_DRAW_L) | (sbofp_st == SST_DRAW_L2);
assign spr_dr = (sbofp_st == SST_DRAW_R) | (sbofp_st == SST_DRAW_R2);

assign sbofp_wsel = ~row[0];

always @* begin
  olb_wa[5] = sbofp_wsel;
  if (sbofp_st == SST_BG) begin
    olb_wa[4:0] = bgr_wa;
    sbofp_wdc_bg = bgr_bgc;
    sbofp_wdc_fg = bgr_fgc;
    sbofp_wds = bgr_px;
    olb_we = bgr_we;
  end
  else begin
    olb_wa[4:0] = spr_dsx[7:3];
    sbofp_wdc_bg = spr_dclr;
    sbofp_wdc_fg = spr_dclr;
    sbofp_wds = 0;
    olb_we = spr_olb_we;
  end
end

always @* begin
  for (int i = 0; i < 8; i++) begin
    olb_wd[(i*4)+:4] = sbofp_wds[i] ? sbofp_wdc_fg : sbofp_wdc_bg;
  end
end

wire [7:0] sbofp_rx;
reg [2:0]  sbofp_rrs;
wire       sbofp_rsel;
wire [3:0] sbofp_px;

assign sbofp_rsel = row[0];
assign sbofp_rx = col[7:0] - 6; // -6 aligns BG+SPR w/ render window left

assign olb_ra = {sbofp_rsel, sbofp_rx[7:3]};
assign olb_re = ~|sbofp_rx[2:0];

always_ff @(posedge CLK) if (CE) begin
  sbofp_rrs <= sbofp_rx[2:0];
end

assign sbofp_px = olb_rd[(sbofp_rrs*4)+:4];


//////////////////////////////////////////////////////////////////////
// Sync generator

reg  de, hsync, vsync, vbl;
reg  de_p;

always_comb begin
  // Enable DE for render region...
  de_p = render_px;
`ifdef EPOCHTV1_BORDERS
  // plus right border...
  if (render_row)
    de_p = de_p | ((col >= FIRST_COL_RIGHT) & (col <= LAST_COL_RIGHT));
  // plus left border.
  if (render_row)
    de_p = de_p | ((col >= FIRST_COL_LEFT) & (col <= LAST_COL_LEFT));
`endif
end

always_ff @(posedge CLK) if (CE) begin
  de <= de_p;
/* verilator lint_off UNSIGNED */
  hsync <= (col >= FIRST_COL_HSYNC) & (col <= LAST_COL_HSYNC);
/* verilator lint_on UNSIGNED */
  vsync <= (row >= FIRST_ROW_VSYNC) & (row <= LAST_ROW_VSYNC);
  vbl <= ~render_row;
end

assign VBL = vbl;
assign DE = de;
assign HS = hsync;
assign VS = vsync;


//////////////////////////////////////////////////////////////////////
// Render pipeline

reg [3:0] pd;
reg       render_visible;

always_ff @(posedge CLK) if (CE) begin
  render_visible <= visible_px;
end

always @* begin
  pd = 4'd1; // black borders
  if (render_visible) begin
    pd = sbofp_px[3:0];
  end
end

assign pre_render_row = (row >= FIRST_ROW_PRE_RENDER) & (row < FIRST_ROW_RENDER);

assign render_row = (row >= FIRST_ROW_RENDER) & (row <= LAST_ROW_RENDER);
assign render_col = (col >= FIRST_COL_RENDER) & (col <= LAST_COL_RENDER);
assign render_px = render_row & render_col;

assign visible_row = (row >= FIRST_ROW_VISIBLE) & (row <= LAST_ROW_VISIBLE);
assign visible_col = (col >= FIRST_COL_VISIBLE) & (col <= LAST_COL_VISIBLE);
assign visible_px = visible_row & visible_col;


//////////////////////////////////////////////////////////////////////
// Color generator

reg [23:0] cg;

always @* begin
  cg = 'X;
  if (CFG_PALETTE == PALETTE_RGB) begin
    // RGB connector signal level is observed to fall off as R+G+B increases.
    case (pd)
	  4'd0 : cg = { 8'd0  , 8'd0  , 8'd160 };
	  4'd1 : cg = { 8'd0  , 8'd0  , 8'd0   };
	  4'd2 : cg = { 8'd0  , 8'd0  , 8'd245 };
	  4'd3 : cg = { 8'd160, 8'd0  , 8'd235 };
	  4'd4 : cg = { 8'd0  , 8'd245, 8'd0   };
	  4'd5 : cg = { 8'd150, 8'd235, 8'd150 };
	  4'd6 : cg = { 8'd0  , 8'd235, 8'd235 };
	  4'd7 : cg = { 8'd0  , 8'd160, 8'd0   };
	  4'd8 : cg = { 8'd245, 8'd0  , 8'd0   };
	  4'd9 : cg = { 8'd235, 8'd160, 8'd0   };
	  4'd10: cg = { 8'd235, 8'd0  , 8'd235 };
	  4'd11: cg = { 8'd235, 8'd150, 8'd150 };
	  4'd12: cg = { 8'd235, 8'd235, 8'd0   };
	  4'd13: cg = { 8'd160, 8'd160, 8'd0   };
	  4'd14: cg = { 8'd150, 8'd150, 8'd150 };
	  4'd15: cg = { 8'd225, 8'd225, 8'd225 };
      default: ;
    endcase
  end
  else if (CFG_PALETTE == PALETTE_RF) begin
    // RF modulator colors are notably different from RGB. Copied from
    // Takeda-san's eSCV emulator [source/src/vm/scv/vdp.cpp].
    case (pd)
	  4'd0 : cg = { 8'd0  , 8'd90 , 8'd156 };
	  4'd1 : cg = { 8'd0  , 8'd0  , 8'd0   };
	  4'd2 : cg = { 8'd58 , 8'd148, 8'd255 };
	  4'd3 : cg = { 8'd0  , 8'd0  , 8'd255 };
	  4'd4 : cg = { 8'd16 , 8'd214, 8'd0   };
	  4'd5 : cg = { 8'd66 , 8'd255, 8'd16  };
	  4'd6 : cg = { 8'd123, 8'd230, 8'd197 };
	  4'd7 : cg = { 8'd0  , 8'd173, 8'd0   };
	  4'd8 : cg = { 8'd255, 8'd41 , 8'd148 };
	  4'd9 : cg = { 8'd255, 8'd49 , 8'd16  };
	  4'd10: cg = { 8'd255, 8'd58 , 8'd255 };
	  4'd11: cg = { 8'd239, 8'd156, 8'd255 };
	  4'd12: cg = { 8'd255, 8'd206, 8'd33  };
	  4'd13: cg = { 8'd74 , 8'd123, 8'd16  };
	  4'd14: cg = { 8'd165, 8'd148, 8'd165 };
	  4'd15: cg = { 8'd255, 8'd255, 8'd255 };
      default: ;
    endcase
  end
end

assign RGB = cg;


endmodule
