# JTYS16 (personal build)

FPGA implementation of Yun Sung's 16-bit board without sound CPU (YS-0211: Paparazzi, Shocking, Bomb Kick,
Magic Bubble YS-0211 PCB) for MiSTer.

- 68000 at 16 MHz, OKI M6295 with 4 x 128 kB banks.
- Two 64x64 tilemaps of 16x16x8 tiles in 256x256 pages, 512 sprites of 16x16x4, 8192-colour palette.
- Behaviour follows MAME's yunsun16.cpp.

Built on [JTFRAME](https://github.com/jotego/jtcores) by Jose Tejada (jotego). GPL-3.0.
