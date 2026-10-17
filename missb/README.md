# JTMISSB (personal build)

Miss Bubble II and Bubble Pong Pong for MiSTer: a bootleg of Bubble Bobble with 8 bpp graphics, a picture background
and an OKI M6295. Based on Jotego's JTBUBL core.

Changes from JTBUBL (MAME missb2.cpp):
- No MCU: the main CPU interrupt comes from vblank and the inputs are read directly at ff00-ff03.
- Sub CPU rewritten for the background: banked ROM data, a 256-colour background palette and the picture register.
- 8 bpp tiles/sprites (two graphics buses read in parallel), pen 0xFF transparent.
- Background layer of 256x16 8 bpp strips with its own palette.
- Sound: YM3526 and OKI M6295 (no YM2203), interrupt at vblank.

Built on [JTFRAME](https://github.com/jotego/jtcores) and JTBUBL by Jose Tejada (jotego). GPL-3.0.
