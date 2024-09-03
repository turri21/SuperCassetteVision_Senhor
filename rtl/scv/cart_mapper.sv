// Cartridge memory mapper
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

import scv_pkg::mapper_t;

module cart_mapper
  (
   input               CLK,

   input               mapper_t MAPPER,

   input [14:0]        A,
   input               RDB,
   input               WRB,
   input               CSB,
   input [6:5]         PC,

   output logic [16:0] ROM_A,
   output              ROM_CSB,

   output logic [12:0] RAM_A,
   output              RAM_CSB
   );

// PC[6:5]: Cartridge-specific function:
//  - 32K ROM + 8K RAM: Overlay RAM enable = PC[5] & &A[14:13]
//  - 64K+ ROM: ROM (32K window) bank select: PC[6:5] => A[16:15]
//  - 128K ROM (+ 4K RAM): ROM (32K window) bank select: PC[6:5] => A[16:15],
//      and Overlay RAM enable = PC[6] & &A[14:12]

logic [16:15] rom_a;
logic [3:0] rom_aw, ram_aw;
logic       ram_en;

always @* begin
  rom_aw = 4'd15;               // 32K ROM
  ram_aw = 4'd13;               // 8K RAM
  ram_en = '0;                  // RAM disabled
  rom_a[16:15] = '0;

  case (MAPPER)
    MAPPER_ROM8K:
      rom_aw = 4'd13;
    MAPPER_ROM16K:
      rom_aw = 4'd14;
    MAPPER_ROM32K: ;
    MAPPER_ROM32K_RAM8K: begin
      // Overlay RAM @ $E000-$FF7F, enable = PC[5]
      ram_en = PC[5] & &A[14:13];
    end
    MAPPER_ROM64K:
      rom_a[15] = PC[5];
    MAPPER_ROM128K:
      rom_a[16:15] = PC[6:5];
    MAPPER_ROM128K_RAM4K: begin
      rom_a[16:15] = PC[6:5];
      // Overlay RAM @ $F000-$FF7F, enable = PC[6]
      ram_aw = 4'd12;
      ram_en = PC[6] & &A[14:12];
    end
    default: ;
  endcase
end

assign ROM_A[16:15] = rom_a[16:15];
assign ROM_A[14:0] = A & ((15'd1 << rom_aw) - 1'd1);
assign ROM_CSB = CSB | ram_en;

assign RAM_A[12:0] = A[12:0] & ((13'd1 << ram_aw) - 1'd1);
assign RAM_CSB = CSB | ~ram_en;

endmodule
