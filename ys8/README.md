# JTYS8 (personal build)

FPGA implementation of Yun Sung's 8-bit board (YS-ROCK-940712: Rock Tris, Magix / Rock, Cannon Ball) for MiSTer.

- Z80 at 8 MHz; sound Z80 at 4 MHz with YM3812 and MSM5205.
- Two fixed 512x256 tilemaps: 8x8x8 background, 8x8x4 text layer. No sprites.
- 384x240 visible. Behaviour follows MAME's yunsung8.cpp.

Built on [JTFRAME](https://github.com/jotego/jtcores) by Jose Tejada (jotego). GPL-3.0.
