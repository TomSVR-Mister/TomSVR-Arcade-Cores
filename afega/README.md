# JTAFEGA: personal MiSTer core for the Afega 8 bpp background boards

Built on JTFRAME by Jose Tejada (jotego), GPL-3.0-or-later. Not affiliated with or supported by jotego.
Hardware description from MAME nmk16.cpp ("popspops" machine, afega_map / afega_sound_cpu).

Games: Bubble 2000, Bubble 2000 V1.2, Hot Bubble (two sets), Pop's Pop's, Mang-Chi.

- 68000 at 12 MHz, program ROM address lines scrambled (undone in the core, header byte 0 bits 1-0)
- Z80 at 4 MHz, YM2151, OKI M6295 at 1 MHz
- 16x16x8 background (256x32 tiles), 8x8x4 text layer, NMK16 sprites with the sprite DMA double buffer
- 6 MHz pixel clock, 384x278, 56.2 Hz, 256x224 visible

The MRAs assemble the ROM from your own MAME zips, unmodified.
