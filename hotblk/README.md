# JTHOTBLK (personal build)

FPGA implementation of the Hot Blocks - Tetrix II board for MiSTer.

- 8088-compatible CPU at 8 MHz (MCL86 core by Ted Fried, MIT licence, as used in the MiSTer PCXT core; the board has a NEC V20).
- 320x200 8-bit frame buffer, 256 colours, AY-3-8910 sound, 24C02 EEPROM. 50 Hz. Behaviour follows MAME's hotblock.cpp.

Built on [JTFRAME](https://github.com/jotego/jtcores) by Jose Tejada (jotego). GPL-3.0 (the MCL86 files keep their MIT licence).
