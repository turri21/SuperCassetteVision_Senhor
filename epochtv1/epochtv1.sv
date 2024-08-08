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
   output [12:0] A,
   input [7:0]   DB_I,
   output [7:0]  DB_O,
   output        DB_OE,
   input         RDB,
   input         WRB,
   input         CSB,
   output [11:0] VAA,
   input [7:0]   VAD_I,
   output [7:0]  VAD_O,
   output        VAD_OE,
   output [11:0] VBA,
   input [7:0]   VBD_I,
   output [7:0]  VBD_O,
   output        VBD_OE,
   output        VBL,
   output        HS,
   output        VS,
   output        DE,
   output [3:0]  COLOR
   );


// Timing is a complete guess. Partially inspired by VIC6560.
localparam [9:0] NUM_ROWS = 9'd262;
localparam [9:0] NUM_COLS = 9'd260;

localparam [9:0] FIRST_ROW_RENDER = 9'd24;
localparam [9:0] LAST_ROW_RENDER = 9'd24 + 9'd192 - 1'd1;
localparam [9:0] FIRST_ROW_VSYNC = 9'd253;
localparam [9:0] LAST_ROW_VSYNC = 9'd261;

localparam [9:0] FIRST_COL_RENDER = 9'd23;
localparam [9:0] LAST_COL_RENDER = 9'd23 + 9'd222 - 1'd1;
localparam [9:0] FIRST_COL_HSYNC = 9'd240;
localparam [9:0] LAST_COL_HSYNC = 9'd259;


reg [8:0]    row, col;
reg          field;


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
// Sync generator

wire render_row = (row >= FIRST_ROW_RENDER) & (row <= LAST_ROW_RENDER);
reg  hsync, vsync, vbl;

always_ff @(posedge CLK) if (CE) begin
  hsync <= (col >= FIRST_COL_HSYNC) & (col <= LAST_COL_HSYNC);
  vsync <= (row >= FIRST_ROW_VSYNC) & (row <= LAST_ROW_VSYNC);
  vbl <= ~render_row;
end

assign HS = hsync;
assign VS = vsync;
assign VBL = vbl;


endmodule
