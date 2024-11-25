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
Acquire these three files:
- upd7801g.s01 (MD5 sum 635a978fd40db9a18ee44eff449fc126)
- epochtv.chr (MD5 sum 929617bc739e58e550fe9025cae4158b)
- upd1771c-017.s03 (MD5 sum 9b03b66c6dc89de9a11d5cd908538ac3)

Concatenate the files to create boot.rom. Windows example:

`COPY /B upd7801g.s01 +epochtv.chr upd1771c-017.s03 boot.rom`

Note: upd1771c-017.s03 is in little-endian order (ROM low byte first).


## Usage

### Keyboard
The console has a numeric keypad called **SELECT**, and a hard **PAUSE** button.

* 0-9 - SELECT numbered keys
* Backspace, numpad ./Del - SELECT **CL** key
* Enter - SELECT **EN** key
* F1 - PAUSE button

### Joysticks
Up to two digital joysticks are mapped to the two controllers. Each controller has two **Trig** buttons.

The most common **SELECT** buttons -- 1 to 4 and **EN** -- can also be configured as joystick buttons.

Most games refer to a **START** button. There is no such button: Use a **Trig** button or **EN** instead.

### Cartridge ROMs

ROM images must:
- Have a file extension .ROM or .BIN
- Be strictly the ROM contents (no headers)

Cartridges had 8K - 128K of ROM, and some had RAM. Two heuristics are used to identify the cartridge -- ROM size and checksum -- and map the memories appropriately. The OSD has an option to manually select a mapper.

#### Special cases
Two cartridges had a mix of ROM sizes. No special mappers exist for them (yet). Create a 64K .BIN file for them as follows:

##### Kung Fu Road
32K ROM + (first 24K [24,576 bytes] of 32K ROM) + 8K ROM --> 64K .BIN

##### Star Speeder
32K ROM + (first 24K [24,576 bytes] of 32K ROM) + 8K ROM --> 64K .BIN


## Known issues


## TODOs
- CPU (uPD7801G)
  - Fix timing of special register instructions (e.g., 'ANI sr2, byte' is 11 steps, should be 17)
- Audio (uPD1771C)
- Cartridges
  - Save and restore battery-backed RAM
  - Make mappers for special cases
