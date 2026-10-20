# JTXEXEX: personal MiSTer core for Konami's Xexex

Built on JTFRAME by Jose Tejada (jotego), GPL-3.0-or-later. Not affiliated with or supported by jotego.
Hardware description from MAME xexex.cpp and its Konami video chip models. Uses jotego's 68000 and Z80 wrappers,
jt51 (YM2151), jt5911 (ER5911 EEPROM), and the K053246/K054321 models from JTSIMSON/JTRIDERS.

Sets: Xexex (ver EAA), Orius (ver UAA), Xexex (ver AAA), Xexex (ver JAA).

- 68000 at 16 MHz, Z80 at 8 MHz, YM2151 and a K054539 PCM model written for this core (jtxexex_k539)
- K056832 tilemaps, K053250 line background, K053246/K053247 sprites, K053251/K054338 mixing with alpha blending
- Game settings live in the EEPROM (saved as NVRAM); change them in the game's test mode
- Checked in simulation against MAME: boot tests, title and attract intro; video frames from MAME dumps match
  about 98% pixel for pixel (the rest is blending rounding)

Build the MRAs with tools/xexex_build.py from your MAME xexex.zip.
