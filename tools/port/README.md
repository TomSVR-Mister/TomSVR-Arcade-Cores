# Comad -> jtgals / jtcomad port tools

Scripts that patch the Comad Gals Panic clones (Fantasia family, New Fantasia, Miss World '96, Super Miss World,
Fantasia II, WOW New Fantasia, Miss World 2002, Super Model I/II, Zip & Zap) to run on Jotego's jtgals core
(or the jtcomad fork with `COMAD=1`) and write the MRAs. No ROM data is kept here.

Setup: unpack your MAME zips into `roms/<set>/` here (or set `COMAD_ROMS`); output goes to `out/` (`out_comad/`
with `COMAD=1`, or `COMAD_OUT`). Needs `m68k-linux-gnu-as`/`objcopy` for `asm/*.s`, and capstone / machine68k for the
reference scans.

- `port.py` - shared library (layout, patching, reference relocation, MRA writer)
- `games_fantasia.py`, `games_c0.py`, `games_lz.py`, `games_lzfull.py`, `games_lzfull_mon.py`, `games_zz.py` - per-family build()
- `g_batch1.py`..`g_batch4.py`, `g_fantasian.py`, `g_full.py`, `g_comad_lz.py`, `g_supmodel.py` - call build() per game
- `refs*.json` - relocated-reference lists; made by `analyze.py` (MAME coverage run), `refs.py` (scan of covered code),
  `refs_ctx.py` (context-validated whole-ROM scan), helped by `extend.py`, `scan.py`, `scan2.py`, `lin.py`
- `leftover.py` - check a built image for unrelocated references; `lzenc.py`, `lzemu.py` - picture LZ codec;
  `facefind.py` - portrait tables
- `asm/` - 68000 patches (sprite converters, picture decompressor, monster-picture DIP, small-face scaler)
