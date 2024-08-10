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
   input         nPARD,
   input         nPAWR,

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


reg [8:0]    row, col;
reg          field;
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


//////////////////////////////////////////////////////////////////////
// Sprite pipeline

// HACK: Embedded VRAM. This will eventually be external.

reg [15:0] vram [2048];

// Object Line Buffer (OLB)
reg [4:0]  olb [256];

reg [7:0]  spr_x;

// TODO: Replace with a clock-driven fill pipeline.
task fill_olb;
integer i, j;
reg [7:0] spr_y0;
reg [3:0] spr_y;
reg [7:0] x;
reg [15:0] pat;
reg px;
s_objattr oa;
  for (i = 0; i < 256; i++) begin
    olb[i] = 0;
  end
  for (i = 0; i < 128; i++) begin
    oa = oam[i];
    spr_y0 = oa.y*2;
    if (row >= spr_y0 && row <= spr_y0 + 15) begin
      spr_y = row - spr_y0;
      for (j = 0; j < 16; j++) begin
        x = oa.x*2 + j;
        pat = vram[{oa.pat, spr_y[3:1], j[3]}];
        px = pat[4'd15 - {~j[2], spr_y[0], j[1:0]}];
        if (px)
          olb[x] = {1'b1, oa.color};
      end
    end
  end
endtask

always @row
  fill_olb();

reg [4:0] spr_px;

assign spr_x = col[7:0];

always @(posedge CLK) if (CE) begin
  if (~render_row) begin
    spr_px <= 0;
  end
  else begin
    spr_px <= olb[spr_x];
  end
end


//////////////////////////////////////////////////////////////////////
// Sync generator

assign render_row = (row >= FIRST_ROW_RENDER) & (row <= LAST_ROW_RENDER);
assign render_col = (col >= FIRST_COL_RENDER) & (col <= LAST_COL_RENDER);
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
