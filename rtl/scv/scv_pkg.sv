// Super Cassette Vision - common definitions
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

`timescale 1us / 1ns

package scv_pkg;

// Human-Machine Interface inputs
typedef struct packed {
  // CONTROLLER buttons (joysticks)
  struct packed {
    bit l, r, u, d;             // directions
    bit t1, t2;                 // L/R orange triggers
  } c1, c2;
  // Console hard buttons (SELECT, PAUSE)
  bit [9:0] num;
  bit cl;
  bit en;
  bit pause;
} hmi_t;

endpackage
