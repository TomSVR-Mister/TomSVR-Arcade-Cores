# JTESD (personal build)

FPGA implementation of ESD's 16-bit arcade boards for MiSTer: Head Panic, Multi Champ, Multi Champ Deluxe,
Deluxe 5 / Deluxe 4 U, Tang Tang and Jumping Pop.

- 68000 at 16 MHz; Z80 at 4 MHz (3.5 MHz on Jumping Pop) with YM3812 and OKI M6295.
- Two scrolling layers of 8x8x8 tiles (128x64) that can switch to 16x16x8 tiles (64x64); DECO-style bootleg sprites, 16x16x5
  (16x16x4 on Jumping Pop) with a priority bit; 2048-colour xRGB palette.
- 93C46 EEPROM on the Head Panic / Multi Champ Deluxe / Deluxe 5 / Tang Tang boards, saved as MiSTer NVRAM.
- Head Panic's tilemap "platform" write port (protection) is implemented.
- 60 Hz, 320x240 visible. Behaviour follows MAME's esd16.cpp.

Built on [JTFRAME](https://github.com/jotego/jtcores) by Jose Tejada (jotego), using his JTOPL, JT6295 and JTEEPROM modules
and fx68k (Jorge Cwik) and T80. GPL-3.0.
