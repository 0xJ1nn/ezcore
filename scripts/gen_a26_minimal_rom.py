#!/usr/bin/env python3
"""Generate a minimal Atari 2600 homebrew program for playability evidence.

Original hand-assembled 6507 machine code (CC0 / public domain), no third-party
content. It clears VBLANK, then cycles COLUBK through 16 colours once per
scanline in an infinite loop, so the frame a core draws is driven by the
program rather than by a fixed startup image.

Why no assembler: this keeps the fixture reproducible on a machine with only
python3. The 6507 is a 6502 without the decimal-adjust ICP; every opcode below
is a base 6502 opcode.

Usage: gen_a26_minimal_rom.py [output.a26]
Default output: native/test-roms/ezcore_a26_minimal.a26
"""
import os
import sys

ORG = 0xF000
ROM_SIZE = 4096

# SEI, CLD, LDX #$FF, TXS                     ; stack init, disable IRQ/decimal
# LDA #$00, STA $01 (VBLANK)                  ; beam on
# loop: STA $02 (WSYNC), INX, TXA, AND #$0F, STA $09 (COLUBK), JMP loop
CODE = bytes([
    0x78, 0xD8, 0xA2, 0xFF, 0x9A,
    0xA9, 0x00, 0x85, 0x01,
    0x85, 0x02, 0xE8, 0x8A, 0x29, 0x0F, 0x85, 0x09,
    0x4C, 0x09, 0xF0,  # JMP $F009 -> the STA WSYNC at loop
])


def main() -> int:
    out = sys.argv[1] if len(sys.argv) > 1 else \
        os.path.join("native", "test-roms", "ezcore_a26_minimal.a26")
    rom = bytearray(ROM_SIZE)
    rom[:len(CODE)] = CODE
    # 6507 vectors: NMI $FFFA, RESET $FFFC, IRQ/BRK $FFFE. For a 4K ROM the
    # file offset is the address minus $F000.
    for vec in (0xFFA, 0xFFC, 0xFFE):
        rom[vec] = ORG & 0xFF
        rom[vec + 1] = ORG >> 8
    parent = os.path.dirname(out)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(out, "wb") as f:
        f.write(rom)
    print(f"Generated {out} ({len(rom)} bytes, {len(CODE)} code bytes)")
    print("  6507 reset vector: $F000, NTSC/PAL auto, 4K bankswitch")
    print("  License: CC0 / public domain (original code)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
