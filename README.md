# Unofficial MiSTer arcade cores (TomSVR)

35 MiSTer arcade cores and 336 MRAs for 1980s and 1990s arcade boards that have no other MiSTer core.

**These are not jotego cores.** Most are built on jotego's JTFRAME framework (megatech, megaplay and mdboot are built on
MegaDrive_MiSTer, nss and snesb on SNES_MiSTer, leland on the official Leland core, see below), but they are not part of jtcores and
jotego does not support them. To avoid confusion, the release files carry a `TomSVR` tag rather than jotego's `jt`
naming. If an official or board-verified core for any of these games comes along, use that one instead; this
project will drop its version.

## How accurate they are

- Each core except megatech, nss and snesb is built on **JTFRAME** and jotego's CPU and sound chip modules (fx68k, T80, jt6295,
  jtopl, jt12, jt51, jt5205, jteeprom, jt5911, jt8051), all unchanged. megatech runs the cartridges on
  **MegaDrive_MiSTer** (Nuked-MD) and adds the Mega-Tech arcade board around it. nss runs the games on **SNES_MiSTer** and adds the NSS
  board (BIOS Z80, security PROM, EEPROM, clock and the M50458 OSD chip) around it. snesb runs the bootleg games on
  **SNES_MiSTer** and adds each bootleg board's ROM descrambling, coin/DIP inputs and protection.
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
| bottom9 | Bottom of the Ninth (Konami, 1989; versions T and N) and Main Stadium (Konami, 1989; Japan), with the K051316 zoom layer and two K007232 sample chips | bottom9.cpp |
| chqflag | Chequered Flag (Konami, 1988; steering by joystick or analog stick) | chqflag.cpp |
| comad | Comad Gals Panic clones (Fantasia (940803 PCB), Fantasia II, Fantasy '95, Hot Night, Miss World '96 / 2002, Super Miss World, Super Model I/II, WOW New Fantasia, Zip & Zap, Gals Hustler, Pocket Gals V.I.P.). Fantasia (940803 PCB), WOW New Fantasia, Super Model I/II and Super Miss World are also published elsewhere; we added them because in our testing that other core shows visual bugs in these games | expro02.cpp |
| djboy | DJ Boy (Kaneko, 1989; World, US and Japan sets) and Air Buster: Trouble Specialty Raid Unit (Kaneko, 1990; World, Japan and bootleg), with the Kaneko Pandora sprite chip, the DJ Boy "BEAST" 80C51 protection MCU and the Air Buster CALC1 chip | djboy.cpp, airbustr.cpp |
| dynduke | Dynamite Duke, The Double Dynamites | dynduke.cpp |
| esd | Multi Champ, Multi Champ Deluxe, Head Panic, Deluxe 5, Tang Tang, Jumping Pop | esd16.cpp |
| funybubl | Funny Bubble | funybubl.cpp |
| gaelco2 | Maniac Square (Gaelco, 1996; protected, unprotected and Snow Board PCB versions), Snow Board Championship (Gaelco / OMK, 1997; versions 2.0 and 2.1), Bang! / Gun Gabacho (Gaelco, 1998; light gun), Touch and Go (Gaelco, 1995-96; one of its two monitors at a time, chosen in the OSD) | gaelco2.cpp |
| galpin | Gals Pinball, Hot Pinball | galspnbl.cpp |
| gumbo | Gumbo, Miss Puzzle, Miss Bingo, Double Point | gumbo.cpp |
| hdoll | Honey Doll | snowbros.cpp |
| hotblk | Hot Blocks - Tetrix II | hotblock.cpp |
| jpop | Jumping Pop (Nics) | tnzs.cpp |
| leland | Leland sports pack on the official Leland core: Viper (trackball), John Elway's Team Quarterback, All American Football and Quarterback (up to 4 players, turned upright on HDMI), World Soccer Finals (4 players). 11 MRAs (see [leland/README_TomSVR.md](leland/README_TomSVR.md)) | leland.cpp |
| madd | Mad Donna, Komo Como | oneshot.cpp |
| mdboot | Mega Drive arcade bootlegs: all 16 working MAME sets (Aladdin, Bare Knuckle I/II/III, Sonic 2, Jurassic Park, Mortal Kombat 3, Super Street Fighter II, Sunset Riders, Contra, the Gunstar Heroes 3-in-1 ...) with each board's coin, DIP switch and protection hardware (see [megatech/README_MDBoot.md](megatech/README_MDBoot.md)). Built in `megatech/` (MDBoot.qpf) | megadriv_acbl.cpp |
| megatech | Sega Mega-Tech: 48 MRAs (38 Mega Drive and 10 Master System cartridges: Golden Axe, Streets of Rage, Sonic 1 and 2, The Revenge of Shinobi, Ghouls'n Ghosts, Out Run, Fantasy Zone ...), one cartridge per MRA, with the real Mega-Tech BIOS running the menu screen, coin timer, TIME UP and test menu; both monitors side by side; settings saved. Built from the board's schematics and decoded PAL chips, with timing measured from real cabinet footage (see [megatech/README_TomSVR.md](megatech/README_TomSVR.md)) | megatech.cpp |
| megaplay | Sega Mega Play: all 12 MAME sets (Sonic 1 and 2, Streets of Rage II, Golden Axe II, Gunstar Heroes, Shinobi III, Bio-hazard Battle ...) with the real Mega Play BIOS drawing its screens over the game, and the 4-slot board: up to 4 games on one menu (see [megatech/README_MegaPlay.md](megatech/README_MegaPlay.md)). Built in `megatech/` (MegaPlay.qpf) | megaplay.cpp |
| missb | Miss Bubble II, Bubble Pong Pong | missb2.cpp |
| nmg5 | Multi 5, Search Eye, Puzzle Club, Garogun Seroyang, 7 Ordi, Wonder Stick | nmg5.cpp |
| nss | Nintendo Super System: 14 MRAs, one per game (Super Mario World, F-Zero, Contra III, ActRaiser, Super Tennis, The Addams Family, Lethal Weapon, Robocop 3 ...) plus two with all three cartridge slots filled (F-Zero / Super Mario World / Super Tennis, and one with all 12 games where you pick each slot's game in the OSD), with the real NSS BIOS running the cabinet (attract mode, game menu, credits, time limit) and its on-screen display drawn over the game (see [nss/README_TomSVR.md](nss/README_TomSVR.md)) | nss.cpp |
| othunder | Operation Thunderbolt (light gun: mouse, analog stick or Sinden; the core draws a crosshair) | othunder.cpp |
| para | Paradise, Target Ball, Torus, Mad Ball, Penky | paradise.cpp |
| pipedrm | Pipe Dream (Video System, 1990; World, US, Japan and Taiwan sets) and Hatris (Video System, 1990; US, Japan and show version), with the YM2608 sound chip built on jt12. Hatris also needs MAME's `ym2608.zip` (the chip's internal drum samples) | pipedrm.cpp |
| playmark | Big Twin, Excelsior, Hot Mind, Hard Times, Lucky Boom | playmark.cpp |
| semicom | SemiCom games: Hyper Pacman, Cookie & Bibi 2 and 3, Toppy & Rappy, Puzzle Break, Su Ho Seong, Twinkle, New HyperMan 3-in-1, Ma Cheon Ru, More More / More More Plus, Final Tetris | snowbros.cpp |
| snesb | SNES arcade bootlegs: 16 MRAs (Killer Instinct, Final Fight 2 and 3, International Superstar Soccer Deluxe, Wild Guns, Gundam Wing - Endless Duel, TMNT Mutant Warriors, Venom & Spider-Man, Sonic Blast Man II, Ghost Chaser Densei, Rushing Beat Shura, Iron, Legend) running on SNES_MiSTer, with each board's ROM scrambling undone while loading and its coin, DIP switch and protection hardware (see [snesb/README_TomSVR.md](snesb/README_TomSVR.md)) | snesb.cpp |
| splash | Splash!, New Splash, Painted Lady, The Return of Lady Frog | splash.cpp |
| sqix | Super Qix (including the 8031 MCU bootleg), Perestroika Girls | superqix.cpp |
| tbowl | Tecmo Bowl (Tecmo, 1987; two World sets, prototype and Japan), up to four players on two monitors: shown side by side or one monitor at a time, chosen in the OSD ("Screens") | tbowl.cpp |
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
`tools/megatech_build.py`. `leland/` is a standalone Quartus project too (`Leland.qpf`, a fork of the official Leland core); its MRAs come
from `tools/leland_build.py`. Every other folder (`esd/`, `para/` ...) is a JTFRAME core. Copy it into `cores/` of
[jotego/jtcores](https://github.com/jotego/jtcores) at commit `bfced64` and build with jotego's normal flow, or run
the `build.yaml` GitHub Actions workflow in this repo. `tools/` holds the MRA generators and the simulation helpers
used to compare against MAME. tbowl also needs its `cfg/jtframe.patch` applied to JTFRAME (it sets the 8:3 aspect ratio when both
monitors are shown side by side).

## Credits and licence

- **Jose Tejada (jotego)**: JTFRAME, jtcores and the chip modules. Three cores are forks of his game cores
  (comad from JTGALS, jpop from JTKIWI, missb from JTBUBL). galpin reuses parts of JTGAIDEN, dynduke the Seibu
  sound from JTTOKI, and xexex the Konami sprite and sound latch models from JTSIMSON / JTRIDERS. bottom9 uses his Konami
  K052109/K051962/K051960 tile and sprite models (JTALIENS), the K051316 register map (JTAJAX) and jt007232.
  djboy runs the DJ Boy protection MCU on his jt8051, with one fix of our own in a renamed copy of its register file
  (`djboy/hdl/jtdjboy_8051_regs.v`: bit instructions such as JBC on the accumulator cleared the whole register).
- **shimian5**: the official MiSTer Leland core ([Arcade-Leland_MiSTer](https://github.com/MiSTer-devel/Arcade-Leland_MiSTer),
  GPL-3), which the leland core forks unchanged apart from the added games and screen rotation.
- **Jorge Cwik**: fx68k. **T80** authors: Z80.
- **Ted Fried (MicroCore Labs)**: MCL86 8088, packaged by Marcus Andrade (openGateware); **Kitune-san**: KF8288.
  Both MIT licensed, used in hotblk.
- **Martin Donlon (wickerwaka)**: the NEC V30 CPU model from the MiSTer Irem M72 core
  ([Arcade-IremM72_MiSTer](https://github.com/MiSTer-devel/Arcade-IremM72_MiSTer)), GPL-2, used in dynduke.
  It is used without asking the author first; if he objects, the dynduke core will be withdrawn.
- **Andrea Bogazzi**: the Video System sprite chip (VS8904/8905), GGA video timing and YM2610 sound structure in
  pipedrm, from his jtpspike core (jotego/jtcores, GPL-3). The Hatris YM2608 is built on jotego's jt12 YM2610B; three of
  its modules are copied and renamed (`pipedrm/hdl/jtpipedrm_opn_top.v`, `_adpcm_drvB.v`, `_adpcmb_cnt.v`).
- **jlrh**: the Gaelco 2 video pipeline (tilemaps, sprites, palette) and GAE1 sound in gaelco2, from his
  [gaelco-fpga](https://github.com/jlrh/gaelco-fpga) Alligator Hunt core (GPLv3). The CPU, memory and inputs are
  JTFRAME; `gaelco2/ORIGIN.md` lists exactly what comes from where and what was changed.
- **nukeykt**: Nuked-MD, the die-level Mega Drive netlists, and **Alexey Melnikov (Sorgelig)**: the MiSTer port
  ([MegaDrive_MiSTer](https://github.com/MiSTer-devel/MegaDrive_MiSTer)), GPL-2.0-or-later, the base of megatech.
  jt89 (jotego) is used for the Mega-Tech menu PSG and T80 for its BIOS Z80. megaplay is built from the same
  source (Mega Play board after MAME megaplay.cpp, BSD-3-Clause, David Haywood), and so is mdboot (bootleg boards
  after MAME megadriv_acbl.cpp, BSD-3-Clause, David Haywood, Stephane Humbert).
- **srg320 and the MiSTer-devel contributors**: [SNES_MiSTer](https://github.com/MiSTer-devel/SNES_MiSTer), GPL-3,
  the base of nss and snesb. **Tomasz Slanina, Peter Ferrie, Stephane Humbert**: MAME snesb.cpp (the bootleg
  boards' scrambling and protection). **nocash (Martin Korth)**: the fullsnes NSS documentation; **DogP**: his NSS research.
- **The MAME team**, whose drivers document these boards.

GPL-3.0-or-later (see `LICENSE`), as required by JTFRAME. The MCL86 and KF8288 files keep their MIT licence,
the V30 files in `dynduke/hdl/v30` keep their GPL-2 licence, and the MegaDrive_MiSTer / Nuked-MD files in
`megatech/` keep their GPL-2.0-or-later licence.
