// Convert HMI inputs to key matrix
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

import scv_pkg::hmi_t;

module hmi2key
  (
   input        hmi_t HMI,

   input [7:0]  KEY_COL,
   output [7:0] KEY_ROW,

   output       PAUSE
   );

wire [7:0] col, row;

// Key matrix
// - Controllers (C1,C2) in columns 0-1
// - Keypad in rows 6-7
//
//    0    1    2  3  4  5  6  7
// 0  C1L  C1D
// 1  C1U  C1R
// 2  C1T1 C1T2
// 3  C2L  C2D
// 4  C2U  C2R
// 5  C2T1 C2T2
// 6            0  2  4  6  8  CL
// 7            1  3  5  7  9  EN

assign col = KEY_COL;

// Pressed buttons short row to column. All rows are pulled high. In
// case of multi-driver contention, low always wins.
assign row[0] = (~HMI.c1.l  | col[0]) & (~HMI.c1.d  | col[1]);
assign row[1] = (~HMI.c1.u  | col[0]) & (~HMI.c1.r  | col[1]);
assign row[2] = (~HMI.c1.t1 | col[0]) & (~HMI.c1.t2 | col[1]);
assign row[3] = (~HMI.c2.l  | col[0]) & (~HMI.c2.d  | col[1]);
assign row[4] = (~HMI.c2.u  | col[0]) & (~HMI.c2.r  | col[1]);
assign row[5] = (~HMI.c2.t1 | col[0]) & (~HMI.c2.t2 | col[1]);

assign row[6] = (~HMI.num[0] | col[2]) & (~HMI.num[2] | col[3]) &
                (~HMI.num[4] | col[4]) & (~HMI.num[6] | col[5]) &
                (~HMI.num[8] | col[6]) & (~HMI.cl | col[7]);
assign row[7] = (~HMI.num[1] | col[2]) & (~HMI.num[3] | col[3]) &
                (~HMI.num[5] | col[4]) & (~HMI.num[7] | col[5]) &
                (~HMI.num[9] | col[6]) & (~HMI.en | col[7]);

assign KEY_ROW = row;

// PAUSE button: 0 = pressed
assign PAUSE = ~HMI.pause;

endmodule
