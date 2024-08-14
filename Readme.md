# [Epoch Super Cassette Vision](https://en.wikipedia.org/wiki/Super_Cassette_Vision) core for [MISTer Platform](https://github.com/MiSTer-devel/Main_MiSTer/wiki)

This is a first-order approximation emulator of the Epoch Super Cassette Vision.

The best documentation I could find is embodied in the [MAME](https://www.mamedev.org) SCV emulator. Takeda-san's [eSCV](http://takeda-toshiya.my.coocan.jp/scv/index.html) and related documents were also very helpful. NEC data sheets of the uCOM-87 microcontroller series were found around the 'net and provided instruction opcodes, cycle timings and other details. The gaps (and there are many) were filled with educated guesses and prior art from building emulators for MOS6502-based machines and the SNES.

It is hoped that, in the future, hardware will be acquired, examined (nicely), and its behavior documented.

## Features
- Just enough to boot the internal ROM, run its built-in video test, and render it.

## Building from source

Today, the boot ROM must be available at FPGA design compile time:
- Acquire upd7801g.s01 (MD5 sum 635a978fd40db9a18ee44eff449fc126)
- Convert to hexadecimal bytes, one per line (as expected by Verilog function $readmemh)
- Copy to rtl/scv/bootrom.hex

These steps will be replaced by a runtime boot.rom loader.

## Installation
(Copy boot.rom...)

## How to build boot.rom
(Placeholder...)

## TODOs
- Load boot.rom
- CPU (uPD7801G)
  - LOTS of instructions
  - Set/clear of and skipping on L0/L1 PSW flags
  - Fix timing of special register instructions (e.g., 'ANI sr2, byte' is 11 steps, should be 17)
- Video (Epoch TV-1)
  - Registers ($3400-3)
  - Background (characters, bitmap)
  - Most sprite features: size, linking, ...
- Controllers
- Audio (uPD1771C)
- Cartridges
