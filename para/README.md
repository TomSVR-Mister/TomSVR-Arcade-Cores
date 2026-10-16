# JTPARA (personal build)

FPGA implementation of Yun Sung's Paradise board (YS-1600 / YS-1604: Paradise, Paradise Deluxe, Paradise 2 Deluxe) for MiSTer.

- Z80 at 6 MHz with 16 kB ROM banking, two OKI M6295.
- Three fixed 256x256 tilemaps (8x8x4 with colour bank, two 8x8x8), a 256x256 4-bit pixel layer, 64 sprites of 16x16x8.
- 54 Hz, 256x224 visible. Behaviour follows MAME's paradise.cpp.

Built on [JTFRAME](https://github.com/jotego/jtcores) by Jose Tejada (jotego). GPL-3.0.
