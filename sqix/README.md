# JTSQIX: personal MiSTer core for the Super Qix board without MCU

Built on JTFRAME by Jose Tejada (jotego), GPL-3.0-or-later. Not affiliated with or supported by jotego.
Hardware description from MAME superqix.cpp ("sqix_nomcu" machine).

Games: Perestroika Girls (Promat, 1994) and its Fuuki license.

- Z80 at 6 MHz with a 4 x 16 kB ROM bank, two AY-3-8910 (inputs and DIP switches on their ports)
- 32x32 8x8 tile map in two priority groups, two 4 bpp 256x224 bitmaps, 64 16x16 sprites, 256-byte BBGGRRII palette
- The byte shuffle of the bootleg's program and graphics ROMs is undone in the core, so the MRAs use your MAME zip unmodified.
