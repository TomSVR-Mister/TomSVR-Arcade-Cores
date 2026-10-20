# JTWRALLY: personal MiSTer core for Gaelco's World Rally

Built on JTFRAME by Jose Tejada (jotego), GPL-3.0-or-later. Not affiliated with or supported by jotego.
Hardware description from MAME wrally.cpp and the Gaelco video/sprite code.

Sets: World Rally (Version 1.0, Checksum 0E56; Version 1.0, Checksum 3873; 0E56 set with the h12/h8 graphics ROMs).

- 68000 at 12 MHz, VRAM writes decrypted on the fly (Gaelco key 0x1f, base XOR 0x522a)
- DS5002FP coprocessor as an 8051 (jt8051) at 12 MHz running the dumped program: all its MOVX accesses go to the
  shared 16 kB RAM, as the game sets it up
- Two 16x16 tile layers with category priority, sprites with shadows, xBRG_444 palette, OKI6295 with ROM banking
- Gear shift toggles on each press of button 2, like the original shifter. Accelerate is button 1.
- Checked in simulation against MAME: boot test, attract, coin up, rally select and stage intro are pixel-identical.

Build the MRAs with tools/wrally_build.py from your MAME wrally.zip.
