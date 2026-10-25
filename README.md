# Unofficial MiSTer arcade cores (TomSVR)

26 MiSTer arcade cores and 245 MRAs for 1980s and 1990s arcade boards that have no other MiSTer core.

**These are not jotego cores.** All but one are built on jotego's JTFRAME framework (megatech is built on
MegaDrive_MiSTer, see below), but they are not part of jtcores and
jotego does not support them. To avoid confusion, the release files carry a `TomSVR` tag rather than jotego's `jt`
naming. If an official or board-verified core for any of these games comes along, use that one instead; this
project will drop its version.

## How accurate they are

- Each core except megatech is built on **JTFRAME** and jotego's CPU and sound chip modules (fx68k, T80, jt6295,
  jtopl, jt12, jt51, jt5205, jteeprom, jt5911, jt8051), all unchanged. megatech runs the cartridges on
  **MegaDrive_MiSTer** (Nuked-MD) and adds the Mega-Tech arcade board around it.
- The board logic on top of that (memory maps, video, sprites, how the chips are wired) was written from the
  **MAME drivers**. No PCBs or schematics were used.
- They were checked by comparing simulation frames against MAME and by playing them on MiSTer hardware. So they
  match MAME's behaviour, but they are **not verified against real boards** the way jotego's cores are.
- They were developed with AI assistance (Claude).

[docs/how_the_cores_are_built.md](docs/how_the_cores_are_built.md) explains, for every core, what it is based on,
which jotego modules it uses, and how its MRAs are laid out.

## Install

**With update_all / downloader (recommended):** add this to `downloader.ini` in the root of the SD card, then run
update_all. It installs the cores to `_Arcade/cores/` and the MRAs to `_Arcade/_TomSVR/`, and keeps them updated.

```ini
[TomSVR-Mister/TomSVR-Arcade-Cores]
db_url = https://raw.githubusercontent.com/TomSVR-Mister/TomSVR-Arcade-Cores/db/db.json.zip
```

To install only some cores, use update_all's download filter with the per-core tags: `arcadetomsvr<core>`
(for example `arcadetomsvresd`, `arcadetomsvrsplash`). Each tag covers one core and its MRAs. Core files are named
`TomSVR_<core>_<build date>.rbf`.

**By hand:** download the zip from the Releases page, then:

1. Copy the `.rbf` files to `/media/fat/_Arcade/cores/`.
2. Copy the `.mra` files to `/media/fat/_Arcade/` (or a subfolder).
3. Put your own MAME (0.264 or later) zips in `/media/fat/games/mame/`. Merged or split sets both work.

Your zips are never modified. Fifteen of the Comad MRAs patch the game program as it loads (see the build document for
why); the patch is applied in memory by the MRA.

## Cores

| Core | Games | MAME driver |
|---|---|---|
| chqflag | Chequered Flag (Konami, 1988; steering by joystick or analog stick) | chqflag.cpp |
| comad | Comad Gals Panic clones (Fantasia (940803 PCB), Fantasia II, Fantasy '95, Hot Night, Miss World '96 / 2002, Super Miss World, Super Model I/II, WOW New Fantasia, Zip & Zap, Gals Hustler, Pocket Gals V.I.P.) | expro02.cpp |
| dynduke | Dynamite Duke, The Double Dynamites | dynduke.cpp |
| esd | Multi Champ, Multi Champ Deluxe, Head Panic, Deluxe 5, Tang Tang, Jumping Pop | esd16.cpp |
| funybubl | Funny Bubble | funybubl.cpp |
| gaelco2 | Maniac Square (Gaelco, 1996; protected, unprotected and Snow Board PCB versions), Snow Board Championship (Gaelco / OMK, 1997; versions 2.0 and 2.1), Bang! / Gun Gabacho (Gaelco, 1998; light gun), Touch and Go (Gaelco, 1995-96; one of its two monitors at a time, chosen in the OSD) | gaelco2.cpp |
| galpin | Gals Pinball, Hot Pinball | galspnbl.cpp |
| gumbo | Gumbo, Miss Puzzle, Miss Bingo, Double Point | gumbo.cpp |
| hdoll | Honey Doll | snowbros.cpp |
| hotblk | Hot Blocks - Tetrix II | hotblock.cpp |
| jpop | Jumping Pop (Nics) | tnzs.cpp |
| madd | Mad Donna, Komo Como | oneshot.cpp |
| megatech | Sega Mega-Tech: 47 games on 48 MRAs (38 Mega Drive and 9 Master System cartridges: Golden Axe, Streets of Rage, Sonic 1 and 2, The Revenge of Shinobi, Ghouls'n Ghosts, Out Run, Fantasy Zone ...), one cartridge per MRA, with the real Mega-Tech BIOS running the menu screen, coin timer, TIME UP and test menu; both monitors side by side; settings saved (see [megatech/README_TomSVR.md](megatech/README_TomSVR.md)) | megatech.cpp |
| missb | Miss Bubble II, Bubble Pong Pong | missb2.cpp |
| nmg5 | Multi 5, Search Eye, Puzzle Club, Garogun Seroyang, 7 Ordi, Wonder Stick | nmg5.cpp |
| othunder | Operation Thunderbolt (light gun: mouse, analog stick or Sinden; the core draws a crosshair) | othunder.cpp |
| para | Paradise, Target Ball, Torus, Mad Ball, Penky | paradise.cpp |
| playmark | Big Twin, Excelsior, Hot Mind, Hard Times, Lucky Boom | playmark.cpp |
| semicom | SemiCom games: Hyper Pacman, Cookie & Bibi 2 and 3, Toppy & Rappy, Puzzle Break, Su Ho Seong, Twinkle, New HyperMan 3-in-1, Ma Cheon Ru, More More / More More Plus, Final Tetris | snowbros.cpp |
| splash | Splash!, New Splash, Painted Lady, The Return of Lady Frog | splash.cpp |
| sqix | Super Qix (including the 8031 MCU bootleg), Perestroika Girls | superqix.cpp |
| wrally | World Rally (Gaelco, 1993) | wrally.cpp |
| xexex | Xexex, Orius | xexex.cpp |
| ys16 | Paparazzi, Shocking, Bomb Kick, Magic Bubble | yunsun16.cpp |
| ys8 | Cannon Ball, Magix / Rock, Rock Tris | yunsung8.cpp |
| zero | Zero Zone, Las Vegas Girl | zerozone.cpp |

`afega/` (Afega boards, already covered by kuzecores) and `pkladies/` (unfinished) are in the source but not released.

Known issues: Miss Puzzle (more explicit) shows some picture corruption. Mega-Tech: Great Soccer is a bad dump in
MAME and stays on a blank screen. Reports are welcome as GitHub issues
(game, MRA name and what you see).

## Building from source

`megatech/` is a standalone Quartus project (`MegaDrive.qpf`, based on MegaDrive_MiSTer); its MRAs come from
`tools/megatech_build.py`. Every other folder (`esd/`, `para/` ...) is a JTFRAME core. Copy it into `cores/` of
[jotego/jtcores](https://github.com/jotego/jtcores) at commit `bfced64` and build with jotego's normal flow, or run
the `build.yaml` GitHub Actions workflow in this repo. `tools/` holds the MRA generators and the simulation helpers
used to compare against MAME.

## Credits and licence

- **Jose Tejada (jotego)**: JTFRAME, jtcores and the chip modules. Three cores are forks of his game cores
  (comad from JTGALS, jpop from JTKIWI, missb from JTBUBL). galpin reuses parts of JTGAIDEN, dynduke the Seibu
  sound from JTTOKI, and xexex the Konami sprite and sound latch models from JTSIMSON / JTRIDERS.
- **Jorge Cwik**: fx68k. **T80** authors: Z80.
- **Ted Fried (MicroCore Labs)**: MCL86 8088, packaged by Marcus Andrade (openGateware); **Kitune-san**: KF8288.
  Both MIT licensed, used in hotblk.
- **Martin Donlon (wickerwaka)**: the NEC V30 CPU model from the MiSTer Irem M72 core
  ([Arcade-IremM72_MiSTer](https://github.com/MiSTer-devel/Arcade-IremM72_MiSTer)), GPL-2, used in dynduke.
  It is used without asking the author first; if he objects, the dynduke core will be withdrawn.
- **jlrh**: the Gaelco 2 video pipeline (tilemaps, sprites, palette) and GAE1 sound in gaelco2, from his
  [gaelco-fpga](https://github.com/jlrh/gaelco-fpga) Alligator Hunt core (GPLv3). The CPU, memory and inputs are
  JTFRAME; `gaelco2/ORIGIN.md` lists exactly what comes from where and what was changed.
- **nukeykt**: Nuked-MD, the die-level Mega Drive netlists, and **Alexey Melnikov (Sorgelig)**: the MiSTer port
  ([MegaDrive_MiSTer](https://github.com/MiSTer-devel/MegaDrive_MiSTer)), GPL-2.0-or-later, the base of megatech.
  jt89 (jotego) is used for the Mega-Tech menu PSG and T80 for its BIOS Z80.
- **The MAME team**, whose drivers document these boards.

GPL-3.0-or-later (see `LICENSE`), as required by JTFRAME. The MCL86 and KF8288 files keep their MIT licence,
the V30 files in `dynduke/hdl/v30` keep their GPL-2 licence, and the MegaDrive_MiSTer / Nuked-MD files in
`megatech/` keep their GPL-2.0-or-later licence.
