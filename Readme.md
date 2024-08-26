# [Epoch Super Cassette Vision](https://en.wikipedia.org/wiki/Super_Cassette_Vision) core for [MISTer Platform](https://github.com/MiSTer-devel/Main_MiSTer/wiki)

This is a first-order approximation emulator of the Epoch Super Cassette Vision.

The best documentation I could find is embodied in the [MAME](https://www.mamedev.org) SCV emulator. Takeda-san's [eSCV](http://takeda-toshiya.my.coocan.jp/scv/index.html) and related documents were also very helpful. NEC data sheets of the uCOM-87 microcontroller series were found around the 'net and provided instruction opcodes, cycle timings and other details. The gaps (and there are many) were filled with educated guesses and prior art from building emulators for MOS6502-based machines and the SNES.

It is hoped that, in the future, hardware will be acquired, examined (nicely), and its behavior documented.

## Features
- Just enough to boot the internal ROM, run its built-in video test, and render it.

## Installation
- Copy the latest *.rbf from releases/ to the root of the SD card
- Build boot.rom (see below)
- Create a folder on the SD card named "SCV" and copy boot.rom to it

### How to build boot.rom
Acquire these two files:
- upd7801g.s01 (MD5 sum 635a978fd40db9a18ee44eff449fc126)
- epochtv.chr (MD5 sum 929617bc739e58e550fe9025cae4158b)

Concatenate the files to create boot.rom. Windows example:

`COPY /B upd7801g.s01 +epochtv.chr boot.rom`


## Usage

### Keyboard
* 0-9 - SELECT numbered keys
* Backspace, numpad ./Del - SELECT CL key
* Enter - SELECT EN key
* F1 - PAUSE button (disabled for now)

### Joysticks
Up to two digital joysticks are mapped to the two controllers. Each controller has two **Trig** buttons.

### Cartridge ROMs

ROM images must:
- Have a file extension .ROM or .BIN
- Be strictly the ROM contents (no headers)


## Known issues
Pressing the PAUSE button hangs the ROM, because the audio chip is not yet implemented. Hence, the button has been disabled for now.

The background is not aligned with the sprites.

Cartridge emulation: Currently hard-wired for a 32K ROM, no RAM. Smaller ROMs can be loaded but won't alias, and so may not work.

## TODOs
- CPU (uPD7801G)
  - Second GP register bank and related instructions (EX, EXX)
  - Set/clear of and skipping on L0/L1 PSW flags
  - Fix timing of special register instructions (e.g., 'ANI sr2, byte' is 11 steps, should be 17)
- Video (Epoch TV-1)
  - Most sprite features: size, linking, ...
- Audio (uPD1771C)
- Cartridges
  - Recognize ROM image on load and set appropriate ROM size, enable RAM, etc.
