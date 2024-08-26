// NEC uPD1771 - a trivial implementation
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

// References:
// . https://github.com/mamedev/mame/blob/master/src/devices/sound/upd1771.cpp - MAME's emulation

// TODO:
// . Everything. This is just a placeholder that ACKs all writes.

`timescale 1us / 1ns

module upd1771
  (
   input       CLK,
   input       RESB,

   input [7:0] DB_I,
   input       WRB,
   input       CSB,

   output      ACK
   );

reg            ack_assert;
wire           write_strobe;
reg [11:0]     ack_cnt;
wire           write;
reg            write_d;
reg [7:0]      db_d, db_d2;
reg [7:0]      cmd, cmd_next;
reg [3:0]      data_cnt, data_cnt_next;
wire           data_more;

initial begin
  ack_assert = 0;
  ack_cnt = 0;
  write_d = 0;
  db_d = 0;
  db_d2 = 0;
  cmd = 0;
  data_cnt = 0;
end

// ACK deasserts on write, and then asserts 512x 6MHz clocks
// later if more data is expected.
always @(posedge CLK) begin
  if (~RESB) begin
    ack_assert <= 0;
    ack_cnt <= 0;
  end
  else begin
    if (write_strobe) begin
      ack_assert <= '0;
      if (data_more)
        ack_cnt <= 12'd2443;        // converted to CLK rate
    end
    else if (|ack_cnt) begin
      if (ack_cnt == 12'd1)
        ack_assert <= '1;
      ack_cnt <= ack_cnt - 1'd1;
    end
  end
end

assign ACK = ack_assert;

// Latch write on WRB de-assertion (posedge).
assign write = ~WRB & ~CSB;
always @(posedge CLK) begin
  if (~RESB) begin
    write_d <= 0;
    db_d <= 0;
    db_d2 <= 0;
  end
  else begin
    write_d <= write;
    db_d <= DB_I;

    // Save last write to catch PCM end marker
    if (write_strobe)
      db_d2 <= db_d;
  end
end

assign write_strobe = write_d & ~write;

always_comb begin
  cmd_next = cmd;
  data_cnt_next = data_cnt;

  case (cmd)
    8'h00: begin                // idle; accept new command
      cmd_next = db_d;
      case (db_d)
        8'h01: data_cnt_next = 4'd9; // NOISE: 10 bytes
        8'h02: data_cnt_next = 4'd3; // TONE: 4 bytes
        8'h1f: data_cnt_next = 4'd1; // PCM: 3+ bytes
        default: data_cnt_next = 0;  // SILENCE or unknown
      endcase
    end
    8'h01, 8'h02:
      data_cnt_next = data_cnt - 1'd1;
    8'h1f:
      if (db_d2 == 8'hfe && db_d == 8'h00) // PCM end marker
        data_cnt_next = 0;
    default: ;
  endcase

  if (data_cnt != 0 && data_cnt_next == 0)
    cmd_next = 0;               // command ended
end

always @(posedge CLK) begin
  if (~RESB) begin
    cmd <= 0;
    data_cnt <= 0;
  end
  else begin
    if (write_strobe) begin
      cmd <= cmd_next;
      data_cnt <= data_cnt_next;

      $display("APU write: %02x  %14s  %s",
               db_d,
               ((cmd != cmd_next) ? ((cmd_next != 0) ? "command start" :
                                     "command end") :
                ((cmd != 0) ? "command active" : "")),
               (data_more ? "ACK" : ""));
    end
  end
end

assign data_more = write_strobe && data_cnt_next != 0;

endmodule
