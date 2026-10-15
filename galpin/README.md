# JTGALPIN (personal build)

FPGA implementation of Comad's Gals Pinball / Hot Pinball boards (1995-96) for MiSTer.

- Main CPU 68000 (11.06 MHz), sound Z80 + YM3812 + OKI M6295 (Tecmo-style sound board).
- Video: 512x256 15-bit RGB bitmap, 64x32 16x8 tilemap, Tecmo sprite chip (bootleg).
- Memory map and video behaviour follow MAME's galspnbl.cpp.

Built on [JTFRAME](https://github.com/jotego/jtcores) by Jose Tejada (jotego). The sprite engine
(jtgalpin_obj*.v) and the sound module are adapted from his JTGAIDEN core. GPL-3.0.
