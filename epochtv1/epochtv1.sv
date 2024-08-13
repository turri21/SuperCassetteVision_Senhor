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

module epochtv1
  (
   input         CLK, // clock (XTAL * 2)
   input         CE, // pixel clock enable

   // CPU address / data bus
   input [12:0]  A,
   input [7:0]   DB_I,
   output [7:0]  DB_O,
   output        DB_OE,
   input         RDB,
   input         WRB,
   input         CSB,

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


// Timing is a complete guess. Partially inspired by VIC6560 (4MHz PCLK).
localparam [8:0] NUM_ROWS = 9'd262;
localparam [8:0] NUM_COLS = 9'd260;

localparam [8:0] FIRST_ROW_RENDER = 9'd21;
localparam [8:0] LAST_ROW_RENDER = 9'd21 + 9'd222 - 1'd1;
localparam [8:0] FIRST_ROW_VSYNC = 9'd253;
localparam [8:0] LAST_ROW_VSYNC = 9'd261;

localparam [8:0] FIRST_COL_RENDER = 9'd28;
localparam [8:0] LAST_COL_RENDER = 9'd28 + 9'd192 - 1'd1;
localparam [8:0] FIRST_COL_HSYNC = 9'd0;
localparam [8:0] LAST_COL_HSYNC = 9'd19;

localparam [8:0] FIRST_ROW_PRE_RENDER = FIRST_ROW_RENDER - 'd2;
// left/right borders
localparam [8:0] FIRST_COL_LEFT = 9'd20;
localparam [8:0] LAST_COL_LEFT = 9'd27;
localparam [8:0] FIRST_COL_RIGHT = 9'd220;
localparam [8:0] LAST_COL_RIGHT = 9'd227;


reg [8:0]    row, col;
reg          field;
wire         pre_render_row;
wire         render_row, render_col, render_px;
wire         cpu_sel_bgm, cpu_sel_oam, cpu_sel_vram, cpu_sel_reg;
wire         cpu_rd, cpu_wr, cpu_rdwr;


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


//////////////////////////////////////////////////////////////////////
// Background memory (BGM)

reg [7:0] bgm [512];

wire [8:0] bgm_a;
reg [7:0]  bgm_rbuf, bgm_wbuf;
wire       bgm_we;

always_ff @(posedge CLK) begin
  bgm_rbuf <= bgm[bgm_a];
  if (bgm_we)
    bgm[bgm_a] <= bgm_wbuf;
end

assign bgm_a = (cpu_sel_bgm & cpu_rdwr) ? A[8:0] : 'X;
assign bgm_we = cpu_sel_bgm & cpu_wr;
assign bgm_wbuf = DB_I;


//////////////////////////////////////////////////////////////////////
// Sprite attribute memory (OAM)

typedef struct packed
{
    reg         split;
    reg [6:0]   pat;
    reg [6:0]   x;
    reg         link_x;
    reg [3:0]   start_line;
    reg [3:0]   color;
    reg [6:0]   y;
    reg         link_y;
} s_objattr;

reg [31:0] oam [128];

reg [6:0] oam_a;
reg [31:0] oam_rbuf;
wire      oam_we;
wire [3:0] oam_ws;
wire [31:0] oam_wbuf;

assign oam_a = (cpu_sel_oam & cpu_rdwr) ? A[8:2] : spr_oam_idx;
assign oam_we = cpu_sel_oam & cpu_wr;
assign oam_wbuf = {4{DB_I}};
assign oam_ws = 4'b1 << A[1:0];

always_ff @(posedge CLK) begin
  oam_rbuf <= oam[oam_a];
  if (oam_we) begin
    for (int i = 0; i < 4; i++) begin
      if (oam_ws[i]) begin
        oam[oam_a][(i*8)+:8] <= oam_wbuf[(i*8)+:8];
      end
    end
  end
end


//////////////////////////////////////////////////////////////////////
// CPU address / data bus interface

reg [7:0] cpu_do;

// Address decoder
assign cpu_sel_vram = ~CSB & (A[12] == 1'b0);     // $0000 - $0FFF
assign cpu_sel_bgm = ~CSB & (A[12:9] == 4'b1000); // $1000 - $11FF
assign cpu_sel_oam = ~CSB & (A[12:9] == 4'b1001); // $1200 - $13FF
assign cpu_sel_reg = ~CSB & (A[12:9] == 4'b1010); // $1400 - $15FF

assign cpu_rd = ~(CSB | RDB);
assign cpu_wr = ~(CSB | WRB);
assign cpu_rdwr = cpu_rd | cpu_wr;

always_ff @(posedge CLK) if (CE) begin
  if (cpu_rd) begin
    if (cpu_sel_vram)
      cpu_do <= A[0] ? VBD_I : VAD_I;
    else if (cpu_sel_bgm)
      cpu_do <= bgm_rbuf;
    else if (cpu_sel_oam)
      cpu_do <= oam_rbuf[(A[1:0]*8)+:8];
    else if (cpu_sel_reg)
      cpu_do <= 0; //TODO
  end
end

assign DB_O = DB_OE ? cpu_do : 8'hzz;
assign DB_OE = cpu_rd;


//////////////////////////////////////////////////////////////////////
// VRAM address / data bus interface

reg [11:0] va;

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
// Background pipeline


//////////////////////////////////////////////////////////////////////
// Object Line Buffer (OLB)
// - 8 pixels wide to enable writing 1/2 sprite in one cycle
// - pixel = 4 bit color + 1 bit opaque
// - two full rows, used in ping-pong fashion
// - olb_rc: clears after read, to prepare for next row

wire [5:0]  olb_wa;
wire [39:0] olb_wd;
reg [7:0]   olb_we;
wire [5:0]  olb_ra;
reg [39:0]  olb_rd;
wire        olb_rc;

reg [39:0]  olb_mem [64];

always_ff @(posedge CLK) if (CE) begin
  for (int i = 0; i < 8; i++) begin
    if (olb_we[i])
      olb_mem[olb_wa][(i*5)+:5] <= olb_wd[(i*5)+:5];
  end
end

always_ff @(posedge CLK) if (CE) begin
  olb_rd <= olb_mem[olb_ra];
  if (olb_rc)
    olb_mem[olb_ra] <= 0;
end


//////////////////////////////////////////////////////////////////////
// Sprite pipeline

enum reg [2:0]
{
 SST_IDLE,
 SST_EVAL,
 SST_DRAW_L,
 SST_DRAW_R
} spr_st;

wire spr_stall;
reg  spr_stall_d;

reg [6:0] spr_oam_idx;

reg spr_olb_wsel;
assign spr_olb_wsel = ~row[0];

wire [15:0] spr_pat;
s_objattr  spr_oa;
reg [11:0] spr_vram_addr;
reg [8:0]  spr_y0;
reg [3:0]  spr_y;
reg        spr_dr;              // sprite left/right side

assign spr_pat = {VBD_I, VAD_I};
assign spr_oa = oam_rbuf;

assign spr_vram_addr = {1'b0, spr_oa.pat, spr_y[3:1], spr_dr};
assign spr_y0 = spr_oa.y*2 - 1'd1;
assign spr_y = 4'(row - spr_y0);
assign spr_dr = spr_st == SST_DRAW_R;

// spr_stall deassertion needs to lag cpu_rdwr deassertion by 1x CE,
// to give memories a chance to recover.
always_ff @(posedge CLK) if (CE) begin
  spr_stall_d <= cpu_rdwr;
end
assign spr_stall = cpu_rdwr | spr_stall_d;

always_ff @(posedge CLK) if (CE) begin
  if (~(pre_render_row | render_row)) begin
    spr_st <= SST_IDLE;
  end
  else if (col == 0) begin
    spr_oam_idx <= 0;
    spr_st <= SST_EVAL;
  end
  else if (~spr_stall) begin
    if (spr_st == SST_EVAL) begin
      spr_st <= SST_EVAL;
    end
    if (spr_st == SST_EVAL) begin
      if (row >= spr_y0 && row <= spr_y0 + 15) begin
        spr_st <= SST_DRAW_L;
      end
      else begin
        spr_st <= (spr_oam_idx < 7'd127) ? SST_EVAL : SST_IDLE;
        spr_oam_idx <= spr_oam_idx + 1'd1;
      end
    end
    else if (spr_st == SST_DRAW_L) begin
      spr_st <= SST_DRAW_R;
    end
    else if (spr_st == SST_DRAW_R) begin
      spr_st <= (spr_oam_idx < 7'd127) ? SST_EVAL : SST_IDLE;
      spr_oam_idx <= spr_oam_idx + 1'd1;
    end
  end
end

reg        spr_dact;
reg [7:0]  spr_dpat;
reg        spr_dact_d, spr_dact_d2;
reg [15:0] spr_dsr;             // draw shift register
reg [7:0]  spr_dsx;             // current drawing column
reg [3:0]  spr_dclr;            // current sprite color

always @* begin
  spr_dpat = 0;
  spr_dact = 0;
  if ((spr_st == SST_DRAW_L) | (spr_st == SST_DRAW_R)) begin
    spr_dact = 1'b1;
    for (int i = 0; i < 8; i++) begin
      spr_dpat[i] = spr_pat[4'd15 - {~i[2], spr_y[0], i[1:0]}];
    end
  end
end

always_ff @(posedge CLK) if (CE) begin
  if (~spr_stall) begin
    spr_dsr <= {spr_dpat, spr_dsr[15:8]};

    spr_dact_d <= spr_dact;
    if (spr_st == SST_DRAW_L) begin
      spr_dsx <= spr_oa.x*2;
      spr_dclr <= spr_oa.color;
    end
    else if (spr_dact_d) begin
      spr_dsx <= spr_dsx + 8'd8;
    end

    spr_dact_d2 <= spr_dact_d;
  end
end

assign olb_wa = {spr_olb_wsel, spr_dsx[7:3]};
assign olb_wd = {8{1'b1, spr_dclr}};

function is_spr_dsr_set(int off);
reg [4:0] p;
  begin
    p = 5'd8 + off[4:0] - 5'(spr_dsx[2:0]);
    is_spr_dsr_set = spr_dsr[4'(p)];
  end
endfunction  

always @* begin
  olb_we = 0;
  if (spr_dact_d | spr_dact_d2) begin
    for (int i = 0; i < 8; i++) begin
      olb_we[i[2:0]] = is_spr_dsr_set(i);
    end
  end
end

wire [7:0] spr_olb_rx;
reg [2:0]  spr_olb_rrs;
wire       spr_olb_rsel;
wire [4:0] spr_px;

assign spr_olb_rsel = row[0];
assign spr_olb_rx = col[7:0];

assign olb_ra = {spr_olb_rsel, spr_olb_rx[7:3]};
assign olb_rc = &spr_olb_rx[2:0];

always_ff @(posedge CLK) if (CE) begin
  spr_olb_rrs <= spr_olb_rx[2:0];
end

assign spr_px = olb_rd[(spr_olb_rrs*5)+:5];


//////////////////////////////////////////////////////////////////////
// Sync generator

reg  de, hsync, vsync, vbl;
reg  visible;

always_comb begin
  // Enable DE for visible region...
  visible = render_px;
`ifdef EPOCHTV1_BORDERS
  // plus right border...
  if (render_row)
    visible = visible | ((col >= FIRST_COL_RIGHT) & (col <= LAST_COL_RIGHT));
  // plus left border.
  if (render_row)
    visible = visible | ((col >= FIRST_COL_LEFT) & (col <= LAST_COL_LEFT));
`endif
end

always_ff @(posedge CLK) if (CE) begin
  de <= visible;
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
reg       render_px_d;

always_ff @(posedge CLK) if (CE) begin
  render_px_d <= render_px;
end

always_comb begin
  pd = 4'd1; // black borders
  if (render_px_d) begin
    pd = spr_px[4] ? spr_px[3:0] : 0;
  end
end

assign pre_render_row = (row >= FIRST_ROW_PRE_RENDER) & (row < FIRST_ROW_RENDER);

assign render_row = (row >= FIRST_ROW_RENDER) & (row <= LAST_ROW_RENDER);
assign render_col = (col >= FIRST_COL_RENDER) & (col <= LAST_COL_RENDER);
assign render_px = render_row & render_col;


//////////////////////////////////////////////////////////////////////
// Color generator

reg [23:0] cg;

always @* begin
  case (pd)
	4'd0 : cg = { 8'd0  , 8'd0  , 8'd155 };
	4'd1 : cg = { 8'd0  , 8'd0  , 8'd0   };
	4'd2 : cg = { 8'd0  , 8'd0  , 8'd255 };
	4'd3 : cg = { 8'd161, 8'd0  , 8'd255 };
	4'd4 : cg = { 8'd0  , 8'd255, 8'd0   };
	4'd5 : cg = { 8'd160, 8'd255, 8'd157 };
	4'd6 : cg = { 8'd0  , 8'd255, 8'd255 };
	4'd7 : cg = { 8'd0  , 8'd161, 8'd0   };
	4'd8 : cg = { 8'd255, 8'd0  , 8'd0   };
	4'd9 : cg = { 8'd255, 8'd161, 8'd0   };
	4'd10: cg = { 8'd255, 8'd0  , 8'd255 };
	4'd11: cg = { 8'd255, 8'd160, 8'd159 };
	4'd12: cg = { 8'd255, 8'd255, 8'd0   };
	4'd13: cg = { 8'd163, 8'd160, 8'd0   };
	4'd14: cg = { 8'd161, 8'd160, 8'd157 };
	4'd15: cg = { 8'd255, 8'd255, 8'd255 };
    default: cg = 'X;
  endcase
end

assign RGB = cg;


endmodule
