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
   output [12:0] A,
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
localparam [9:0] NUM_ROWS = 9'd262;
localparam [9:0] NUM_COLS = 9'd260;

localparam [9:0] FIRST_ROW_RENDER = 9'd21;
localparam [9:0] LAST_ROW_RENDER = 9'd21 + 9'd222 - 1'd1;
localparam [9:0] FIRST_ROW_VSYNC = 9'd253;
localparam [9:0] LAST_ROW_VSYNC = 9'd261;

localparam [9:0] FIRST_COL_RENDER = 9'd28;
localparam [9:0] LAST_COL_RENDER = 9'd28 + 9'd192 - 1'd1;
localparam [9:0] FIRST_COL_HSYNC = 9'd0;
localparam [9:0] LAST_COL_HSYNC = 9'd19;

localparam [9:0] FIRST_ROW_PRE_RENDER = FIRST_ROW_RENDER - 'd2;


reg [8:0]    row, col;
reg          field;
wire         pre_render_row;
wire         render_row, render_col;


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


//////////////////////////////////////////////////////////////////////
// Background pipeline


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

s_objattr oam [128];

s_objattr  oam_rbuf;
always_ff @(posedge CLK) begin
  oam_rbuf <= oam[spr_oam_idx];
end


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

reg [6:0] spr_oam_idx;

reg spr_olb_wsel;
assign spr_olb_wsel = ~row[0];

wire [15:0] pat;
reg [11:0] spr_vram_addr;
reg [7:0]  spr_y0;
reg [3:0]  spr_y;
reg        spr_dr;              // sprite left/right side

assign VAA = spr_vram_addr;
assign nVARD = 1'b0;
assign nVAWR = 1'b1;
assign VBA = spr_vram_addr;
assign nVBRD = 1'b0;
assign nVBWR = 1'b1;
assign pat = {VBD_I, VAD_I};

assign spr_vram_addr = {oam_rbuf.pat, spr_y[3:1], spr_dr};
assign spr_y0 = oam_rbuf.y*2 - 1'd1;
assign spr_y = row - spr_y0;
assign spr_dr = spr_st == SST_DRAW_R;

always_ff @(posedge CLK) if (CE) begin
  if (~(pre_render_row | render_row)) begin
    spr_st <= SST_IDLE;
  end
  else if (col == 0) begin
    spr_oam_idx <= 0;
    spr_st <= SST_EVAL;
  end
  else begin
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
      spr_dpat[i] = pat[4'd15 - {~i[2], spr_y[0], i[1:0]}];
    end
  end
end

always_ff @(posedge CLK) if (CE) begin
  spr_dsr <= {spr_dpat, spr_dsr[15:8]};

  spr_dact_d <= spr_dact;
  if (spr_st == SST_DRAW_L) begin
    spr_dsx <= oam_rbuf.x*2;
    spr_dclr <= oam_rbuf.color;
  end
  else if (spr_dact_d) begin
    spr_dsx <= spr_dsx + 8'd8;
  end

  spr_dact_d2 <= spr_dact_d;
end

assign olb_wa = {spr_olb_wsel, spr_dsx[7:3]};
assign olb_wd = {8{1'b1, spr_dclr}};

always @* begin
  olb_we = 0;
  if (spr_dact_d | spr_dact_d2) begin
    for (int i = 0; i < 8; i++) begin
    reg [4:0] p;
      p = 5'd8 + i[4:0] - spr_dsx[2:0];
      olb_we[i[2:0]] = spr_dsr[p];
    end
  end
end

wire [7:0] spr_olb_rx;
reg [7:0]  spr_olb_rrs;
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

always_ff @(posedge CLK) if (CE) begin
  de <= render_row & render_col;
  hsync <= (col >= FIRST_COL_HSYNC) & (col <= LAST_COL_HSYNC);
  vsync <= (row >= FIRST_ROW_VSYNC) & (row <= LAST_ROW_VSYNC);
  vbl <= ~render_row;
end

assign VBL = vbl;
assign DE = de;
assign HS = hsync;
assign VS = vsync;


//////////////////////////////////////////////////////////////////////
// Render pipeline

wire [3:0] pd = spr_px[4] ? spr_px[3:0] : 0;

assign pre_render_row = (row >= FIRST_ROW_PRE_RENDER) & (row < FIRST_ROW_RENDER);

assign render_row = (row >= FIRST_ROW_RENDER) & (row <= LAST_ROW_RENDER);
assign render_col = (col >= FIRST_COL_RENDER) & (col <= LAST_COL_RENDER);


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
