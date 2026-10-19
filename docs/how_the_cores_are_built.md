# How the 18 released cores are put together

This covers the 18 released cores and their 114 MRAs. File names in releases carry a `TomSVR` tag; the core
folders and module names below keep their JTFRAME `jt` names because the framework needs them.

## The common base

All 18 cores are JTFRAME cores. Each repo folder (`esd/`, `para/` ...) is copied into
`jotego/jtcores/cores/` at commit `bfced64` and built there with jotego's normal build flow. So every core
depends on jtcores at that commit. Nothing in jotego's tree is changed; the cores only add new folders.

Each core folder has the same JTFRAME layout:

| File | What it does |
|---|---|
| `hdl/jt<core>_game.v` | Top level of the game. It reads the MRA header bytes and wires up the CPUs, video and sound. |
| `hdl/jt<core>_main.v`, `_sound.v`, `_video.v` ... | The board logic, written from MAME's driver for that board. |
| `cfg/macros.def` | Screen size, pixel clock, rotation, button count and the ROM download layout. |
| `cfg/mem.yaml` | SDRAM banks, block RAMs, and which jotego sound chips are mixed in at what level. |
| `cfg/files.yaml` | The shared modules the core pulls from jtcores (listed per core below). |

What JTFRAME provides to every core:

- The MiSTer system wrapper: OSD, video output and scalers, inputs, DIP switches, the ROM download, NVRAM saving and the credits screen.

- The SDRAM controller and ROM caches generated from `mem.yaml`.

- The audio mixer and filters.

- The CPU wrappers:

  - `jtframe_m68k` wraps Jorge Cwik's fx68k 68000.

  - `jtframe_z80` wraps the T80 Z80.

- Common video helpers where a core uses them: the video timer, line buffers, the sprite draw engine and tile layouts.

jotego's separate chip modules, all unchanged:

| Module | Chip |
|---|---|
| jt6295 | OKI M6295 ADPCM |
| jtopl (`jtopl2`, `jt26`) | YM3812 / YM3526 |
| jt12 (`jt03`, `jt49`) | YM2203, AY-3-8910 |
| jt51 | YM2151 |
| jt5205 | MSM5205 ADPCM |
| jteeprom | 93C46 serial EEPROM |

## The cores

The cores fall into three groups by origin.

### Forks of a jotego core (3)

These began as a copy of one of jotego's game cores, renamed and changed. The original jotego core is untouched.

| Core | Started from | Main changes |
|---|---|---|
| **jtcomad** (13 MRAs) | **JTGALS** (Kaneko Gals Panic) | 5 MB program ROM plus a 1 MB patch ROM at B00000. Work RAM at C80000. OKI moved to A80000. MAME's palette-based fg transparency. Header bit 1 selects the Afega Gals Hustler board (Pocket Gals V.I.P., Gals Hustler), which reads VU-002 sprites natively. Uses jtframe_m68k, jtframe_obj, jt6295. |
| **jtjpop** (1) | **JTKIWI** (Taito TNZS / Seta X1) | Jumping Pop (Nics): JT51 YM2151 on the second CPU in place of the YM2203, inputs and DIP switches on the second CPU, a 1024-entry palette, dial support from JTKIWI. Keeps JTKIWI's Z80s and i8742 MCU module (upi41), jt03 and jt51. |
| **jtmissb** (2) | **JTBUBL** (Bubble Bobble) | Miss Bubble II and Bubble Pong Pong. No MCU, a rewritten sub CPU for the picture background, 8 bpp tiles and sprites, and YM3526 + OKI in place of the YM2203. Z80s, jt26, jt6295. |

### New cores that reuse pieces of a jotego core (1)

| Core | Reused from | Notes |
|---|---|---|
| **jtgalpin** (2) | **JTGAIDEN** | Gals Pinball / Hot Pinball. The Tecmo sprite engine (`jtgalpin_obj*.v`) and the sound board module are adapted from JTGAIDEN. The bitmap, tilemap, memory map and colour mixer are new, from MAME's galspnbl.cpp. 68000 + Z80 + YM3812 + OKI. |

### New board cores on JTFRAME (14)

Each of these is a new driver written from the MAME source named, using only JTFRAME and the chip modules above.

| Core | MRAs | Board (MAME driver) | CPUs | Sound | jotego modules used |
|---|---|---|---|---|---|
| **jtesd** | 20 | ESD 16-bit (esd16.cpp) | 68000, Z80 | YM3812, OKI | m68k, z80, jtopl2, jt6295, jteeprom (93C46 NVRAM) |
| **jtfunybubl** | 2 | Funny Bubble (funybubl.cpp) | Z80, Z80 | OKI | z80, jt6295 |
| **jtgumbo** | 8 | Min Corp. (gumbo.cpp) | 68000 | OKI | m68k, jt6295 |
| **jthdoll** | 1 | Honey Doll (snowbros.cpp) | 68000, Z80 | YM3812, OKI | m68k, z80, jtopl2, jt6295 |
| **jthotblk** | 3 | Hot Blocks (hotblock.cpp) | 8088 | AY-3-8910 | jt49 only (no JTFRAME CPU). See below. |
| **jtmadd** | 2 | Promat VISYS (oneshot.cpp) | 68000, Z80 | YM3812 | m68k, z80, jtopl2 |
| **jtnmg5** | 12 | Yun Sung YS-1300 (nmg5.cpp) | 68000, Z80 | YM3812, OKI | m68k, z80, jtopl2, jt6295 |
| **jtpara** | 13 | Yun Sung Paradise (paradise.cpp) | Z80 | 2 x OKI | z80, jt6295, jtframe_edge |
| **jtplaymark** | 5 | Playmark (playmark.cpp) | 68000, PIC16C57 | OKI | m68k, jt6295, jteeprom (Hot Mind). The PIC16C57 is new code (`jtplaymark_pic.v`, from the Microchip data sheet and MAME). |
| **jtsplash** | 11 | Gaelco Splash! (splash.cpp) | 68000, Z80 | YM3812, MSM5205; YM2203 for Lady Frog | m68k, z80, jtopl2, jt5205, jt03, jtframe obj draw |
| **jtsqix** | 2 | Super Qix without MCU (superqix.cpp) | Z80 | 2 x AY-3-8910 | z80, jt49. The bootleg's ROM byte shuffle is undone in the core. |
| **jtys16** | 10 | Yun Sung 16-bit (yunsun16.cpp) | 68000 (+ Z80 on Magic Bubble) | OKI, YM3812 | m68k, z80, jt6295, jtopl2, jtframe obj draw |
| **jtys8** | 5 | Yun Sung 8-bit (yunsung8.cpp) | Z80, Z80 | YM3812, MSM5205 | z80, jtopl2, jt5205 |
| **jtzero** | 2 | Comad 1993 (zerozone.cpp) | 68000, Z80 | OKI | m68k, z80, jt6295 |

### Code not from jotego

- **jthotblk** uses the **MCL86** 8088 core by Ted Fried (MicroCore Labs), as packaged by Marcus Andrade (openGateware), and **KF8288** by Kitune-san. Both are MIT licensed and kept as copies in `hotblk/hdl/`. This is the only core that uses no JTFRAME CPU wrapper. The board's 24C02 EEPROM is a small new I2C module.

- **fx68k** (Jorge Cwik) and **T80** come with JTFRAME and are used through jotego's wrappers.

- Everything else is new code (2026), written against MAME 0.264-era drivers.

### Licence

All of the cores are GPL-3.0, as JTFRAME and jtcores require. The MCL86 and KF8288 files keep their MIT licence.

## The MRAs

All the MRAs follow the same scheme, with a few exceptions listed at the end.

### How every MRA is laid out

- **`rom index="0"`: the game ROM.** It starts with a 4-byte header part on 13 of the cores. The rest is assembled from your MAME zip in the order set by that core's `macros.def` (`JTFRAME_BA1_START` and so on). Steps include byte swaps for 68000 programs, `interleave` for 16- and 32-bit graphics, and `repeat` padding to fill each slot.

- **`rom index="1"`: default DIP switches.** The `<switches>` block (97 of the 114 MRAs) gives the OSD menu.

- **`rom index="2"` with `<nvram>`:** this appears on the 14 JTESD MRAs whose board has a 93C46 EEPROM. It loads MAME's default `.nv` file from the zip, and after that MiSTer saves your own. Hot Mind and Hot Blocks have EEPROMs too, but their MRAs don't preload one.

- **`<buttons>`:** named buttons. The count must match `JTFRAME_BUTTONS`, or a button lands on Select. (This caused a coin bug on Big Twin / Hot Mind, now fixed.)

- **Zip names:** current MAME names and merged sets. Clones look in the parent zip. `mameversion` is 0264 on 74 MRAs, 0282 on 37 (the Comad ones) and 0270 on 3.

### What the header bytes select, per core

One core can run several board variants because the header tells it which one it is loading:

| Core | Header meaning |
|---|---|
| jtcomad | byte 0 bit 1: Gals Hustler board (Afega) |
| jtesd | byte 0 bits 2-0: memory map (Head Panic, Multi Champ Deluxe, Tang Tang / Deluxe 5, Multi Champ, Jumping Pop); bit 3: 08-26-1999 PCB sprite offsets; bits 5-4: sprite tile count; bit 6: EEPROM byte order; bit 7: 2 MB tile ROM |
| jtgumbo | byte 0: memory map (Gumbo, Miss Puzzle / Bingo, Double Point); byte 1: big background / foreground |
| jtjpop | byte 1 bit 6: Nics board |
| jtmadd | byte 0 bit 0: Komo Como layer order |
| jtmissb | byte 0 bit 0: Bubble Pong Pong background layout |
| jtnmg5 | byte 0: Puzzle Club map, 16 MB tile ROM, sprite tile count, Multi 5 / 7 Ordi input quirks, 55 Hz (Search Eye Plus); byte 1: protection value |
| jtpara | byte 0: tile and sprite layout flags; byte 1: board mode and bank mask |
| jtplaymark | byte 0 bit 0: Excelsior; bit 1: Hot Mind (Hard Times board) |
| jtsplash | byte 0 bit 0: Splash! 1.0 sprite attribute; bit 1: The Return of Lady Frog |
| jtys16 | byte 0 bit 0: Magic Bubble YS1302 board |
| jtys8 | byte 0 bit 0: 2 MB background; bit 1: Cannon Ball vertical |
| jthotblk | header present, all zero |
| jtfunybubl, jtgalpin, jthdoll, jtsqix, jtzero | no header (one board layout) |

### Exceptions to know about

- **Ten JTCOMAD MRAs patch the program as it loads** (Fantasia II x3, Fantasy '95, Hot Night, Miss World '96 set 1, Miss World 2002 x2, WOW New Fantasia Explicit, Zip & Zap Less Explicit). Most carry about 1,150 to 1,190 `<patch>` lines (Zip & Zap 111). The patches relocate work RAM and add code in the 1 MB extension ROM that converts the VU-002 sprite list to the Pandora format each frame. Your zip is never changed. Nothing needs to be applied by hand: the MRA does it at load time. The three Gals Hustler / Pocket Gals MRAs run unpatched because the core reads that board's sprites natively.

- **jtsqix** undoes the bootleg's byte shuffle inside the core, so its MRAs are a plain copy of the zip.

- **jtplaymark** loads the PIC16C57 sound program from MAME's hex dump as the PROM section.

- **How they were made:** Most MRAs are hand-made and were tested on real MiSTer hardware. jthdoll, jtfunybubl and jtplaymark MRAs come from `tools/<core>_build.py`. jotego's `jtframe mra` generator is not used, because its layouts don't match these cores.
