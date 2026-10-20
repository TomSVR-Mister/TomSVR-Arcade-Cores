# JTOTHUNDER: personal MiSTer core for Taito's Operation Thunderbolt

Built on JTFRAME by Jose Tejada (jotego), GPL-3.0-or-later. Not affiliated with or supported by jotego.
Hardware description from MAME othunder.cpp.

Sets: Operation Thunderbolt (World rev 1, World, US rev 1, US, Japan, Japan SC).

- 68000 at 13.3 MHz, Z80 sound CPU with a YM2610 (jt10), TC0100SCN tile layers, sprites through a sprite map ROM
- Light gun game: aim with a mouse, light gun or the left analog stick; button 1 fires, button 2 launches a rocket.
  The game draws no crosshair (the cabinet has mounted guns), so the MRA turns on the JTFRAME crosshair.
- 93C46 EEPROM saved as NVRAM
- The picture is mirrored like the original cabinet, which is viewed through a mirror.

Build the MRAs with tools/othunder_build.py from your MAME othunder.zip.
