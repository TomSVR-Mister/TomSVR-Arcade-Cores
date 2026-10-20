# JTSQIX: personal MiSTer core for the Super Qix board

Built on JTFRAME by Jose Tejada (jotego), GPL-3.0-or-later. Not affiliated with or supported by jotego.
Hardware description from MAME superqix.cpp ("sqix" with the i8751 MCU and "sqix_nomcu").

Games: Super Qix (Kaneko / Taito, 1987: World-Japan V1.2, V1.1, V1.0, US, and the no-MCU bootleg),
Perestroika Girls (Promat, 1994) and its Fuuki license.

- Z80 at 6 MHz with a 4 x 16 kB ROM bank, two AY-3-8910 (inputs and DIP switches on their ports)
- i8751 MCU at 6 MHz (jt8051) running the dumped program: it reads the coins, starts and DIP switch 1, holds the Z80
  in reset until it is ready, and talks to the Z80 through AY port B with two semaphore flags
- 32x32 8x8 tile map in two priority groups, two 4 bpp 256x224 bitmaps, 64 16x16 sprites, 256-byte BBGGRRII palette
- Header byte 0: bit 0 Perestroika Girls byte shuffle, bit 1 MCU fitted.
- The byte shuffle of the Perestroika Girls program and graphics ROMs is undone in the core, so the MRAs use your
  MAME zip unmodified.
