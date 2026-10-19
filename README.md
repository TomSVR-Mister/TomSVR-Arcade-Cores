# Unofficial MiSTer arcade cores (TomSVR)

18 MiSTer arcade cores and 114 MRAs for small 1990s arcade boards that have no other MiSTer core.

**These are not jotego cores.** They are built on jotego's JTFRAME framework, but they are not part of jtcores and
jotego does not support them. To avoid confusion, the release files carry a `TomSVR` tag rather than jotego's `jt`
naming. If an official or board-verified core for any of these games comes along, use that one instead; this
project will drop its version.

## How accurate they are

- Each core is built on **JTFRAME** and jotego's CPU and sound chip modules (fx68k, T80, jt6295, jtopl, jt12, jt51,
  jt5205, jteeprom), all unchanged.
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

**By hand:** download the zip from the Releases page, then:

1. Copy the `.rbf` files to `/media/fat/_Arcade/cores/`.
2. Copy the `.mra` files to `/media/fat/_Arcade/` (or a subfolder).
3. Put your own MAME (0.264 or later) zips in `/media/fat/games/mame/`. Merged or split sets both work.

Your zips are never modified. Ten of the Comad MRAs patch the game program as it loads (see the build document for
why); the patch is applied in memory by the MRA.

## Cores

| Core | Games | MAME driver |
|---|---|---|
| comad | Comad Gals Panic clones (Fantasia II, Fantasy '95, Hot Night, Miss World '96 / 2002, Zip & Zap, Gals Hustler, Pocket Gals V.I.P.) | expro02.cpp |
| esd | Multi Champ, Multi Champ Deluxe, Head Panic, Deluxe 5, Tang Tang, Jumping Pop | esd16.cpp |
| funybubl | Funny Bubble | funybubl.cpp |
| galpin | Gals Pinball, Hot Pinball | galspnbl.cpp |
| gumbo | Gumbo, Miss Puzzle, Miss Bingo, Double Point | gumbo.cpp |
| hdoll | Honey Doll | snowbros.cpp |
| hotblk | Hot Blocks - Tetrix II | hotblock.cpp |
| jpop | Jumping Pop (Nics) | tnzs.cpp |
| madd | Mad Donna, Komo Como | oneshot.cpp |
| missb | Miss Bubble II, Bubble Pong Pong | missb2.cpp |
| nmg5 | Multi 5, Search Eye, Puzzle Club, Garogun Seroyang, 7 Ordi, Wonder Stick | nmg5.cpp |
| para | Paradise, Target Ball, Torus, Mad Ball, Penky | paradise.cpp |
| playmark | Big Twin, Excelsior, Hot Mind | playmark.cpp |
| splash | Splash!, New Splash, Painted Lady, The Return of Lady Frog | splash.cpp |
| sqix | Perestroika Girls | superqix.cpp |
| ys16 | Paparazzi, Shocking, Bomb Kick, Magic Bubble | yunsun16.cpp |
| ys8 | Cannon Ball, Magix / Rock, Rock Tris | yunsung8.cpp |
| zero | Zero Zone, Las Vegas Girl | zerozone.cpp |

`afega/` (Afega boards, already covered by kuzecores) and `pkladies/` (unfinished) are in the source but not
released.

Known issue: Miss Puzzle (more explicit) shows some picture corruption. Reports are welcome as GitHub issues
(game, MRA name and what you see).

## Building from source

Each folder (`esd/`, `para/` ...) is a JTFRAME core. Copy it into `cores/` of
[jotego/jtcores](https://github.com/jotego/jtcores) at commit `bfced64` and build with jotego's normal flow, or run
the `build.yaml` GitHub Actions workflow in this repo. `tools/` holds the MRA generators and the simulation helpers
used to compare against MAME; `HANDOVER.md` has developer notes.

## Credits and licence

- **Jose Tejada (jotego)**: JTFRAME, jtcores and the chip modules. Three cores are forks of his game cores
  (comad from JTGALS, jpop from JTKIWI, missb from JTBUBL) and galpin reuses parts of JTGAIDEN.
- **Jorge Cwik**: fx68k. **T80** authors: Z80.
- **Ted Fried (MicroCore Labs)**: MCL86 8088, packaged by Marcus Andrade (openGateware); **Kitune-san**: KF8288.
  Both MIT licensed, used in hotblk.
- **The MAME team**, whose drivers document these boards.

GPL-3.0-or-later (see `LICENSE`), as required by JTFRAME. The MCL86 and KF8288 files keep their MIT licence.
