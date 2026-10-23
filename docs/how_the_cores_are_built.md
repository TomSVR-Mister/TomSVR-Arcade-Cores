# How the 22 released cores are put together

This covers the 25 released cores and their 193 MRAs. File names in releases carry a `TomSVR` tag; the core
folders and module names below keep their JTFRAME `jt` names because the framework needs them.

## The common base

All 25 cores are JTFRAME cores. Each repo folder (`esd/`, `para/` ...) is copied into
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
| jt12 (`jt03`, `jt10`, `jt49`) | YM2203, YM2610, AY-3-8910 |
| jt51 | YM2151 |
| jt5205 | MSM5205 ADPCM |
| jteeprom, jt5911 | 93C46 / ER5911 serial EEPROM |
| jt8051 | 8051 family MCU (i8751, DS5002FP) |

## The cores

The cores fall into three groups by origin.

### Forks of a jotego core (3)

These began as a copy of one of jotego's game cores, renamed and changed. The original jotego core is untouched.

| Core | Started from | Main changes |
|---|---|---|
| **jtcomad** (14 MRAs) | **JTGALS** (Kaneko Gals Panic) | 5 MB program ROM plus a 1 MB patch ROM at B00000. Work RAM at C80000. OKI moved to A80000. MAME's palette-based fg transparency. Header bit 1 selects the Afega Gals Hustler board (Pocket Gals V.I.P., Gals Hustler), which reads VU-002 sprites natively. Uses jtframe_m68k, jtframe_obj, jt6295. |
| **jtjpop** (1) | **JTKIWI** (Taito TNZS / Seta X1) | Jumping Pop (Nics): JT51 YM2151 on the second CPU in place of the YM2203, inputs and DIP switches on the second CPU, a 1024-entry palette, dial support from JTKIWI. Keeps JTKIWI's Z80s and i8742 MCU module (upi41), jt03 and jt51. |
| **jtmissb** (2) | **JTBUBL** (Bubble Bobble) | Miss Bubble II and Bubble Pong Pong. No MCU, a rewritten sub CPU for the picture background, 8 bpp tiles and sprites, and YM3526 + OKI in place of the YM2203. Z80s, jt26, jt6295. |

### New cores that reuse pieces of a jotego core (3)

| Core | Reused from | Notes |
|---|---|---|
| **jtdynduke** (7) | **JTTOKI** | Dynamite Duke. The Seibu sound board (Z80 with SEI80BU decryption, YM3812, OKI) comes from JTTOKI. Two NEC V30 CPUs from the MiSTer Irem M72 core (GPL-2, see below). Text, two scroll layers and sprites are new, from MAME's dynduke.cpp. |
| **jtxexex** (4) | **JTSIMSON / JTRIDERS** | Xexex and Orius. The K053246 sprite DMA and register blocks and the K054321 sound latch come from those cores. K056832 tilemaps, K053250 line background, K053251/K054338 mixing with alpha and a new K054539 PCM model are new, from MAME's xexex.cpp. 68000, Z80, jt51, jt5911 EEPROM saved as NVRAM. |
| **jtgalpin** (2) | **JTGAIDEN** | Gals Pinball / Hot Pinball. The Tecmo sprite engine (`jtgalpin_obj*.v`) and the sound board module are adapted from JTGAIDEN. The bitmap, tilemap, memory map and colour mixer are new, from MAME's galspnbl.cpp. 68000 + Z80 + YM3812 + OKI. |

### New board cores on JTFRAME (16)

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
| **jtgaelco2** | 5 | Gaelco 2 boards (gaelco2.cpp): Maniac Square, Snow Board Championship | 68000, DS5002FP on the protected sets | GAE1 / CG1V (on the video chip) | m68k (jtframe_m68k), jt8051 (with a fix to its bit instructions, see `gaelco2/ORIGIN.md`), jt9346 EEPROM, JTFRAME RAMs. Video and GAE1 sound from jlrh's gaelco-fpga, extended with the fifth graphics plane, the 384-pixel screen and MAME's vblank sprite buffer. |
| **jtpara** | 13 | Yun Sung Paradise (paradise.cpp) | Z80 | 2 x OKI | z80, jt6295, jtframe_edge |
| **jtplaymark** | 9 | Playmark (playmark.cpp) | 68000, PIC16C57 | OKI | m68k, jt6295, jteeprom (Hot Mind). The PIC16C57 is new code (`jtplaymark_pic.v`, from the Microchip data sheet and MAME). |
| **jtothunder** | 6 | Taito Operation Thunderbolt (othunder.cpp) | 68000, Z80 | YM2610 | m68k, z80, jt10, jteeprom (93C46 NVRAM). Light gun game; the MRA sets the JTFRAME light gun flag so a crosshair is drawn for mouse, stick or Sinden aiming. |
| **jtsemicom** | 19 | SemiCom games on the Snow Bros-style board (snowbros.cpp) | 68000, Z80; AT89C52 MCU on Hyper Pacman and Cookie & Bibi 2 | YM2151, OKI | m68k, z80, jt51, jt6295, jt8051 (runs the dumped AT89C52 program, which writes the protection data into work RAM). Kaneko Pandora sprites are new code. The other protected sets copy a 0x200-byte data block from the MRA into work RAM at reset, as MAME does. |
| **jtsplash** | 11 | Gaelco Splash! (splash.cpp) | 68000, Z80 | YM3812, MSM5205; YM2203 for Lady Frog | m68k, z80, jtopl2, jt5205, jt03, jtframe obj draw |
| **jtsqix** | 8 | Super Qix, Perestroika Girls (superqix.cpp) | Z80, i8751 MCU | 2 x AY-3-8910 | z80, jt49, jt8051 running the dumped MCU program. The bootleg's ROM byte shuffle is undone in the core. |
| **jtwrally** | 9 | Gaelco World Rally (wrally.cpp) | 68000, DS5002FP | OKI | m68k, jt8051 (DS5002FP running the dumped program), jt6295. VRAM writes are decrypted on the fly. |
| **jtchqflag** | 2 | Konami Chequered Flag (chqflag.cpp) | 052001 (jtkcpu), Z80 | YM2151, 2 x 007232 | jtkcpu, z80, jt51, jt007232, K051960 sprites and K051733 from jotego's cores. Two K051316 zoom/rotate layers start from jt051316 (JTAJAX); the 8 bpp road layer fetches two pixels at a time from two SDRAM banks. Known issue: thin streaks at the right end of the road on some rotated views. |
| **jtys16** | 10 | Yun Sung 16-bit (yunsun16.cpp) | 68000 (+ Z80 on Magic Bubble) | OKI, YM3812 | m68k, z80, jt6295, jtopl2, jtframe obj draw |
| **jtys8** | 5 | Yun Sung 8-bit (yunsung8.cpp) | Z80, Z80 | YM3812, MSM5205 | z80, jtopl2, jt5205 |
| **jtzero** | 2 | Comad 1993 (zerozone.cpp) | 68000, Z80 | OKI | m68k, z80, jt6295 |

### Code not from jotego

- **jthotblk** uses the **MCL86** 8088 core by Ted Fried (MicroCore Labs), as packaged by Marcus Andrade (openGateware), and **KF8288** by Kitune-san. Both are MIT licensed and kept as copies in `hotblk/hdl/`. This is the only core that uses no JTFRAME CPU wrapper. The board's 24C02 EEPROM is a small new I2C module.

- **jtgaelco2** uses the Gaelco 2 video pipeline and the GAE1 sound model from **jlrh's gaelco-fpga** (GPLv3,
  Alligator Hunt core), with fixes; the CPU, bus, RAMs and inputs are JTFRAME. `gaelco2/ORIGIN.md` has the details.

- **jtdynduke** uses the **NEC V30** model by Martin Donlon (wickerwaka) from the MiSTer Irem M72 core, GPL-2, kept in `dynduke/hdl/v30` with its licence. It is used without asking the author first; if he objects, the core will be withdrawn.

- **fx68k** (Jorge Cwik) and **T80** come with JTFRAME and are used through jotego's wrappers.

- Everything else is new code (2026), written against MAME 0.264-era drivers.

### Licence

All of the cores are GPL-3.0, as JTFRAME and jtcores require. The MCL86 and KF8288 files keep their MIT licence, and the V30 files keep their GPL-2 licence.

## The MRAs

All the MRAs follow the same scheme, with a few exceptions listed at the end.

### How every MRA is laid out

- **`rom index="0"`: the game ROM.** It starts with a 4-byte header part on 13 of the cores. The rest is assembled from your MAME zip in the order set by that core's `macros.def` (`JTFRAME_BA1_START` and so on). Steps include byte swaps for 68000 programs, `interleave` for 16- and 32-bit graphics, and `repeat` padding to fill each slot.

- **`rom index="1"`: default DIP switches.** The `<switches>` block gives the OSD menu. On jtothunder `rom index="1"` instead carries the JTFRAME core flags (`02 00` = light gun, which turns on the crosshair).

- **`rom index="2"` with `<nvram>`:** this appears on the 14 JTESD MRAs whose board has a 93C46 EEPROM, and on the Xexex and Operation Thunderbolt MRAs. It saves the EEPROM to the SD card; the JTESD ones also preload MAME's default `.nv` file from the zip. Hot Mind and Hot Blocks have EEPROMs too, but their MRAs don't preload one.

- **`<buttons>`:** named buttons. The count must match `JTFRAME_BUTTONS`, or a button lands on Select. (This caused a coin bug on Big Twin / Hot Mind, now fixed.)

- **Zip names:** current MAME names and merged sets. Clones look in the parent zip. `mameversion` is 0264 on 131 MRAs, 0282 on 38 (the Comad ones), 0288 on 5 (Gaelco 2) and 0270 on 3.

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
| jtplaymark | byte 0 bit 0: Excelsior; bit 1: Hard Times board; bits 3-2 with bit 1: 0 Hot Mind, 1 Hard Times, 2 Lucky Boom, 3 Big Twin (No Girls Conversion) |
| jtsemicom | byte 0 bits 1-0: value read at 0x200000; bit 2: protection data at 0x102000 (Final Tetris); bit 3: active-low inputs (Final Tetris); bit 4: MCU writes at 0x10e000 (Hyper Pacman) |
| jtsplash | byte 0 bit 0: Splash! 1.0 sprite attribute; bit 1: The Return of Lady Frog |
| jtys16 | byte 0 bit 0: Magic Bubble YS1302 board |
| jtys8 | byte 0 bit 0: 2 MB background; bit 1: Cannon Ball vertical |
| jthotblk | header present, all zero |
| jtdynduke | byte 0 bit 0: The Double Dynamites I/O map |
| jtgaelco2 | byte 0: graphics plane size (0x80000 << n); byte 1/4/5: planes 2-3 / 0-1 / 4 read as zero from word byte << 16; byte 2: sound bank to plane map; byte 3: bit 0 DS5002FP, bit 1 Snow Board board, bit 2 384-pixel screen, bit 3 fifth plane, bit 4 15 MHz CPU, bit 5 Bang! light-gun board, bit 6 Touch and Go board (480-pixel dual monitor, 16 MHz, 4 players) |
| jtsqix | byte 0 bit 0: Perestroika Girls ROM byte shuffle; bit 1: MCU fitted; bit 2: the bootleg's 8031 MCU in place of the i8751 |
| jtfunybubl, jtgalpin, jthdoll, jtothunder, jtwrally, jtxexex, jtzero | no header (one board layout) |

### Exceptions to know about

- **Eleven JTCOMAD MRAs patch the program as it loads** (Fantasia 940803 PCB, Fantasia II x3, Fantasy '95, Hot Night, Miss World '96 set 1, Miss World 2002 x2, WOW New Fantasia Explicit, Zip & Zap Less Explicit). Most carry about 1,150 to 1,190 `<patch>` lines (Zip & Zap 111). The patches relocate work RAM and add code in the 1 MB extension ROM that converts the VU-002 sprite list to the Pandora format each frame. Your zip is never changed. Nothing needs to be applied by hand: the MRA does it at load time. The three Gals Hustler / Pocket Gals MRAs run unpatched because the core reads that board's sprites natively.

- **jtsqix** undoes the bootleg's byte shuffle inside the core, so its MRAs are a plain copy of the zip.

- **jtplaymark** loads the PIC16C57 sound program from MAME's hex dump as the PROM section (Hard Times: MAME's binary dump).

- **How they were made:** Most MRAs are hand-made and were tested on real MiSTer hardware. jthdoll, jtfunybubl and jtplaymark MRAs come from `tools/<core>_build.py`. jotego's `jtframe mra` generator is not used, because its layouts don't match these cores.
