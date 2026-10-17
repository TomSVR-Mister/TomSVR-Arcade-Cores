# JTNMG5 (personal build)

FPGA implementation of Yun Sung's YS-1300 family (Multi 5 / New Multi Game 5, Puzzle Club, Wonder Stick) for MiSTer.

- 68000 at 16 MHz; Z80 at 4 MHz with YM3812 and OKI M6295.
- Two 64x64 tilemaps of 8x8x8 tiles, DECO-style bootleg sprites (16x16x5), 512x256 4-bit pixel layer, priority register.
- 60 Hz, 320x240 visible. Behaviour follows MAME's nmg5.cpp.

Built on [JTFRAME](https://github.com/jotego/jtcores) by Jose Tejada (jotego). GPL-3.0.
