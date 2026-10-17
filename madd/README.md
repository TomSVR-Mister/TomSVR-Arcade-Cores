# JTMADD (personal build)

FPGA implementation of the Promat / Tuning "VISYS" board (Mad Donna, Komo Como) for MiSTer.

- 68000 at 12 MHz; Z80 at 3.375 MHz with YM3812 (the OKI M6295 has no samples on these games).
- Three 32x32 tilemaps of 16x16x8 tiles, sprites built from 8x8x8 blocks (up to 16x16 blocks), 1024 colours.
- 56 Hz, 320x240 visible. Behaviour follows MAME's oneshot.cpp.

Built on [JTFRAME](https://github.com/jotego/jtcores) by Jose Tejada (jotego). GPL-3.0.
