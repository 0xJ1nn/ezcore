#!/usr/bin/env python3
"""Generate a minimal NES test ROM for ezCORE.

Creates an original NROM-128 (mapper 0) NES ROM that renders a solid
background color. This is intentionally simple — it proves the emulator
can boot, render pixels, and produce a frame without needing any
copyrighted game content.

The ROM is original code (no copyrighted material) and is released
under CC0 / public domain.

Output: native/test-roms/ezcore_nes_minimal.nes
"""

import os
import sys


def main():
    # ---- iNES header (16 bytes) ----
    header = bytearray(16)
    header[0:4] = b'NES\x1A'  # Magic number
    header[4] = 1             # 1 x 16KB PRG ROM
    header[5] = 1             # 1 x 8KB CHR ROM
    header[6] = 0x01          # Flags 6: vertical mirroring, no battery, mapper 0 low
    header[7] = 0x00          # Flags 7: mapper 0 high, no NES 2.0
    # header[8:16] = 0 (padding)

    # ---- PRG ROM (16384 bytes, mapped at $C000-$FFFF) ----
    prg = bytearray(16384)

    # ---- CHR ROM (8192 bytes) — all zeros = blank tile ----
    chr_rom = bytearray(8192)

    # ---- 6502 machine code (placed at $C000) ----
    code = bytearray()

    # sei — disable interrupts
    code.append(0x78)
    # cld — clear decimal mode
    code.append(0xD8)
    # ldx #$FF
    code.extend([0xA2, 0xFF])
    # txs — initialize stack pointer to $FF
    code.append(0x9A)

    # lda #$00
    code.extend([0xA9, 0x00])
    # sta $2000 — PPUCTRL = 0 (disable NMI, standard mode)
    code.extend([0x8D, 0x00, 0x20])
    # sta $2001 — PPUMASK = 0 (disable rendering during warmup)
    code.extend([0x8D, 0x01, 0x20])

    # Wait for PPU to warm up (two vblanks required after power-on)
    # bit $2002 (read PPU status to reset latch)
    code.extend([0x2C, 0x02, 0x20])
    # wait1:
    #   bit $2002
    code.extend([0x2C, 0x02, 0x20])
    #   bpl wait1  (loop until bit 7 = 1, i.e., vblank started)
    code.extend([0x10, 0xFB])
    # bit $2002 (reset latch again)
    code.extend([0x2C, 0x02, 0x20])
    # wait2:
    #   bit $2002
    code.extend([0x2C, 0x02, 0x20])
    #   bpl wait2
    code.extend([0x10, 0xFB])

    # Set background palette color to dark blue ($02)
    # lda #$3F
    code.extend([0xA9, 0x3F])
    # sta $2006 — PPU address high byte ($3F)
    code.extend([0x8D, 0x06, 0x20])
    # lda #$00
    code.extend([0xA9, 0x00])
    # sta $2006 — PPU address low byte ($00) → points to $3F00 (palette)
    code.extend([0x8D, 0x06, 0x20])
    # lda #$02 — dark blue color index
    code.extend([0xA9, 0x02])
    # sta $2007 — write to palette RAM
    code.extend([0x8D, 0x07, 0x20])

    # Enable background + sprites rendering
    # lda #$1E — show bg + sprites + leftmost 8px
    code.extend([0xA9, 0x1E])
    # sta $2001
    code.extend([0x8D, 0x01, 0x20])

    # Enable NMI (so the PPU can signal vblank)
    # lda #$80
    code.extend([0xA9, 0x80])
    # sta $2000
    code.extend([0x8D, 0x00, 0x20])

    # Infinite loop — PPU continues rendering autonomously
    loop_offset = len(code)
    # jmp loop
    code.extend([0x4C])
    loop_addr = 0xC000 + loop_offset
    code.extend([loop_addr & 0xFF, (loop_addr >> 8) & 0xFF])

    # Place code at the start of PRG ROM ($C000)
    prg[:len(code)] = code

    # ---- Interrupt vectors at $FFFA-$FFFF ----
    # NMI vector at $FFFA → $C000
    prg[0x3FFA] = 0x00
    prg[0x3FFB] = 0xC0
    # Reset vector at $FFFC → $C000
    prg[0x3FFC] = 0x00
    prg[0x3FFD] = 0xC0
    # IRQ vector at $FFFE → $C000
    prg[0x3FFE] = 0x00
    prg[0x3FFF] = 0xC0

    # ---- Write ROM file ----
    output_dir = 'native/test-roms'
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, 'ezcore_nes_minimal.nes')

    with open(output_path, 'wb') as f:
        f.write(bytes(header))
        f.write(bytes(prg))
        f.write(bytes(chr_rom))

    size = os.path.getsize(output_path)
    print(f"Generated {output_path} ({size} bytes)")
    print(f"  Header:  16 bytes")
    print(f"  PRG ROM: 16384 bytes (16KB, mapped at $C000-$FFFF)")
    print(f"  CHR ROM: 8192 bytes (8KB, blank tiles)")
    print(f"  Code:    {len(code)} bytes")
    print(f"  Reset vector: $C000")
    print(f"  Mapper:  0 (NROM-128)")
    print(f"  Mirroring: vertical")
    print(f"  License: CC0 / public domain (original code)")

    return 0


if __name__ == '__main__':
    sys.exit(main())
