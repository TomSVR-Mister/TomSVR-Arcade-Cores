# JTCHQFLAG: personal MiSTer core for Konami's Chequered Flag

Built on JTFRAME by Jose Tejada (jotego), GPL-3.0-or-later. Not affiliated with or supported by jotego.
Hardware description from MAME chqflag.cpp; the K051316 zoom/rotate layers start from jotego's jt051316 (JTAJAX).

Sets: Chequered Flag (International), Chequered Flag (Japan).

- 052001 (Konami 6809 variant, jtkcpu) main CPU, Z80 sound CPU with a YM2151 and two 007232 PCM chips
- Two K051316 zoom/rotate layers (4 bpp and 8 bpp), K051960 sprites, K051733 protection
- Known issue: on some rotated views the right end of the road layer can show thin streaks.

Build the MRAs with tools/chqflag_build.py from your MAME chqflag.zip.
