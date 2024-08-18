// Connect joysticks and keyboard to HMI
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

import scv_pkg::hmi_t;

module joykey
  (
   input        CLK_SYS,

   input [31:0] JOYSTICK_0,
   input [31:0] JOYSTICK_1,

   input [10:0] PS2_KEY,

   output       hmi_t HMI
   );

wire ps2_toggle = PS2_KEY[10];
wire pressed = PS2_KEY[9];
reg  ps2_toggle_d;

initial begin
  HMI = 0;
  ps2_toggle_d = 0;
end

always @(posedge CLK_SYS) begin
  if (ps2_toggle ^ ps2_toggle_d) begin
    case (PS2_KEY[8:0])
      // TODO: Enable pause when sound bypassed/working
      //'h005:        HMI.pause <= pressed; // F1
      'h045, 'h070: HMI.num[0] <= pressed;
      'h016, 'h069: HMI.num[1] <= pressed;
      'h01E, 'h072: HMI.num[2] <= pressed;
      'h026, 'h07A: HMI.num[3] <= pressed;
      'h025, 'h06B: HMI.num[4] <= pressed;
      'h02E, 'h073: HMI.num[5] <= pressed;
      'h036, 'h074: HMI.num[6] <= pressed;
      'h03D, 'h06C: HMI.num[7] <= pressed;
      'h03E, 'h075: HMI.num[8] <= pressed;
      'h046, 'h07D: HMI.num[9] <= pressed;
      'h066, 'h071: HMI.cl <= pressed; // Backspace, (keypad) ./Del
      'h05A, 'h15A: HMI.en <= pressed; // Enter, (keypad) Enter
      default: ;
    endcase
  end

  ps2_toggle_d <= ps2_toggle;
end

assign {HMI.c1.t2, HMI.c1.t1,
        HMI.c1.u, HMI.c1.d, HMI.c1.l, HMI.c1.r} = JOYSTICK_0[5:0];
assign {HMI.c2.t2, HMI.c2.t1,
        HMI.c2.u, HMI.c2.d, HMI.c2.l, HMI.c2.r} = JOYSTICK_1[5:0];

endmodule
