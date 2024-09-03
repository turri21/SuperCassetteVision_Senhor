// Cartridge ID
//
// Identify the cartridge by the ROM size and contents, and report the
// appropriate mapper.
//
// Copyright (c) 2024 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

import scv_pkg::mapper_t;

module cart_id
  (
   input        CLK,

   input [4:0]  ROM_SIZE_LOG2,
   input [31:0] ROM_CKSUM,

   input        mapper_t IN_MAPPER,
   output       mapper_t OUT_MAPPER
   );

logic rom32k_ram8k, rom128k_ram4k;
mapper_t id_mapper;

// These 32K ROM cartridges have 8K RAM.
always_comb begin
  case (ROM_CKSUM)
    32'h002aa39f,               // BASIC Nyuumon (1985)(Epoch)(JP)(en)
    32'h002da24f,               // Dragon Slayer (1986)(Epoch)(JP)(en)
    32'h003016e4,               // Pop & Chips (1985)(Epoch)(JP)(en)
    32'h002df73d:               // Shogi Nyuumon (1985)(Epoch)(JP)
      rom32k_ram8k = '1;
    default: rom32k_ram8k = '0;
  endcase
end

// These 32K ROM cartridges have 8K RAM.
always_comb begin
  case (ROM_CKSUM)
    32'h01384995:            // Pole Position II (1985)(Epoch)(JP)(en)
      rom128k_ram4k = '1;
    default: rom128k_ram4k = '0;
  endcase
end

// Pick the appropriate mapper.
always_comb begin
  case (ROM_SIZE_LOG2)
    5'd13: id_mapper = MAPPER_ROM8K;
    5'd14: id_mapper = MAPPER_ROM16K;
    5'd15: begin
      id_mapper = MAPPER_ROM32K;
      if (rom32k_ram8k)
        id_mapper = MAPPER_ROM32K_RAM8K;
    end
    5'd16: id_mapper = MAPPER_ROM64K;
    5'd17: begin
      id_mapper = MAPPER_ROM128K;
      if (rom128k_ram4k)
        id_mapper = MAPPER_ROM128K_RAM4K;
    end
    default: id_mapper = MAPPER_ROM32K;    // most functional default
  endcase
end

// User may override our findings.
always_comb begin
  if (IN_MAPPER == MAPPER_AUTO)
    OUT_MAPPER = id_mapper;
  else
    OUT_MAPPER = IN_MAPPER;
end


endmodule
