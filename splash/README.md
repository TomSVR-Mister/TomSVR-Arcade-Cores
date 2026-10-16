# JTSPLASH (personal build)

FPGA implementation of Gaelco's Splash! board (1992: Splash!, Painted Lady, New Splash) for MiSTer.

- 68000 at 12 MHz; Z80 at 3.75 MHz with YM3812 and MSM5205.
- 512x256 8-bit pixel layer, 64x32 8x8 and 32x32 16x16 tilemaps, 256 sprites of 16x16x4.
- 58 Hz, 368x240 visible. Behaviour follows MAME's splash.cpp.

Built on [JTFRAME](https://github.com/jotego/jtcores) by Jose Tejada (jotego). GPL-3.0.
