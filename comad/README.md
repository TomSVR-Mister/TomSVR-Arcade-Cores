# JTCOMAD: personal fork of JTGALS (Jose Tejada / jotego) for the Comad Gals Panic clones

Not affiliated with or supported by jotego. Original core: https://github.com/jotego/jtcores (cores/gals), GPL-3.0-or-later.

Changes from JTGALS:

1. CPU ROM is 000000-4FFFFF (5 MB, as on the Comad boards) instead of 000000-3FFFFF,
   plus a 1 MB extension ROM at CPU B00000-BFFFFF for patch code (unused by the original games).
   Download layout: header (4 bytes), game ROM 0x000000-0x4FFFFF, extension 0x500000-0x5FFFFF,
   OKI samples 0x600000-0x6FFFFF, sprites 0x700000-0x7FFFFF. CPU RAM in SDRAM at word offset 0x300000.
2. Work RAM at C80000-C8FFFF (64 KB, as on the Comad boards), backed by SDRAM. Lets games such as Zip & Zap keep
   their RAM where it is instead of being patched.
3. OKI M6295 moved from 400000 to A80000 (400000 is now ROM).
4. Foreground transparency follows MAME expro02: a fg pixel is drawn unless bit 0 of its palette entry is set
   (JTGALS treats fg value 0 as transparent). Fixes the picture flash when the game blanks the palette.

Build: GitHub Actions workflow "Build Comad core" (Actions tab -> Run workflow). The .rbf is in the run's artifacts.

5. Header byte 0 bit 1 ("gh") selects the Afega Gals Hustler board (MAME expro02 "galhustl": Pocket Gals V.I.P., Gals Hustler):
   program 000000-0FFFFF + data 200000-2FFFFF, work RAM E80000, OKI D00000, IRQ 3/4/5 at lines 224/112/0,
   and the VU-002 sprite list at 700000 read natively (MAME kaneko16 bootleg_draw_sprites). These games run unpatched.
