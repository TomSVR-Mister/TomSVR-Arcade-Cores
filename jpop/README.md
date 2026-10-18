# JTJPOP (personal build)

Jumping Pop (Nics, 1992), a Korean hack of Taito's Plump Pop, for MiSTer. Based on Jotego's JTKIWI core
(Taito TNZS / Seta X1 hardware).

Changes from JTKIWI (MAME tnzs.cpp, jpopnics):
- YM2151 (Jotego's JT51) on the second CPU instead of the YM2203; no sound NMI.
- Inputs at c000/c001 and DIP switches at c600/c601 read directly by the second CPU; dial counters reset by bank bit 5.
- 1024-entry palette RAM at f800-ffff, GBRx_444 big-endian (MAME's interpretation).
- Controls: spinner/dial (JTFRAME dial support from JTKIWI, with joystick emulation).

Built on [JTFRAME](https://github.com/jotego/jtcores) and JTKIWI by Jose Tejada (jotego). GPL-3.0.
