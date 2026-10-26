# TomSVR_megatech: Sega Mega-Tech for MiSTer

Unofficial MiSTer core for the Sega Mega-Tech arcade system (MAME driver `sega/megatech.cpp`), released as
TomSVR_megatech. One cartridge per MRA (48 MRAs: 38 Mega Drive and 10 Master System based sets).

As far as we know this is the first FPGA Mega-Tech, and it goes further than MAME, where every Mega-Tech set is
still marked "not working" (MAME never stops the game when the time runs out).

## What works

- **The real Mega-Tech BIOS runs the cabinet**: menu screen with the game instructions, credits, coin timer
  (a coin buys play time), the end-of-time warnings and the return to attract mode, all from the original BIOS
  and instruction ROMs, as on the board.
- **TIME UP**: when the time runs out the game stops, "TIME UP" is shown for about 4 seconds, the screen goes black
  and the game restarts in attract mode, without the picture losing sync.
- **Time warnings**: the last-seconds alarm and the screen flash (OSD "Flash Warning": Dim or the VDP's Shadow
  mode).
- **Master System cartridges** run on the Mega Drive's SMS mode, as on the real board (Out Run, Fantasy Zone,
  Shinobi, After Burner ...).
- **Test menu** (TEST MODE): bookkeeping, data clear, input, coin chute and output tests, DIP switch assignments
  and alarm/flash time set, shown on the main screen as on the cabinet.
- **Settings and bookkeeping are saved** to the SD card (battery-backed RAM of the board; saved when the OSD opens).
- **Two monitors**: OSD "Screen" shows the game or the menu monitor, and **Side by Side** shows both at once
  (game left, menu right).
- Cabinet buttons on the pad and keyboard.

## How it was built

- **Starting point:** MegaDrive_MiSTer (Nuked-MD) runs the game side. MAME's `megatech.cpp` gave the set list,
  ROM layouts, the BIOS memory map, DIP switches and inputs.
- **The board itself, where MAME is incomplete:** the owner's manual, the schematic and partial KiCad board traces,
  the CXD1095 I/O chip datasheet and the cabinet pinout. The board's PAL logic chips (315-5346/5347B/5348A/5349A/
  5356) were decoded from dumps; one dump's checksum had to be repaired first. The PALs show what MAME misses: when
  port D bit 7 is 0, the BIOS Z80 reaches the Mega Drive's own bus. That is how TIME UP and the test menu appear on
  the main monitor rather than on the menu monitor.
- **Real cabinet footage:** frame-by-frame grabs of video from a working cabinet gave the behaviour MAME doesn't
  have: the warning flash every 12 frames, TIME UP held for about 3.8 seconds, then the restart into attract mode.
- **Cycle-level simulation:** the BIOS and both video chips ran in Verilator simulations and were checked against
  MAME traces. The menu, instruction and TIME UP screens and the Sonic game screen are pixel-identical to MAME, and
  boot, coin and select timing match. The BIOS code was traced there to find what the hardware must do, for example
  the test-menu screen routing and a VDP status-flag timing detail that broke the test menu's input.
- **MRAs:** generated from `megatech.cpp` by tools/megatech_build.py. Each image is rebuilt the way MiSTer assembles
  it and compared with MAME's ROM layout; all 48 match.

## Up to 8 games at once (cartridge slots)

The real Mega-Tech board holds up to 8 cartridges, and players pick between them on the menu screen. The core does
the same. This feature is in testing and arrives with the next core update.

- **Slot 1** is always the game of the MRA you start.
- **Slots 2-8** are filled from the core's OSD menu with cartridge files (`.mtc`). MiSTer remembers your choice for
  each MRA and loads the same cartridges at every start.

**Why .mtc files?** An MRA builds a cartridge from your MAME zips when the core starts, but only for its own game.
The OSD file loader can't open zips. A `.mtc` file is a cartridge assembled ahead of time: exactly the image the
MRA would build, in one file. It contains ROM data, so it is not distributed; you make them from your own zips.

**Making the .mtc files (once):**
1. Copy `tools/megatech_mtc.py` and `tools/megatech_make_mtc.sh` from this repository to `/media/fat/Scripts/` on
   your MiSTer SD card.
2. On the MiSTer, open the Scripts menu and run **megatech_make_mtc**. It reads the Mega-Tech MRAs in
   `_Arcade` and its subfolders and your zips in `games/mame` (megatech.zip is not needed), and writes one file
   per game to `games/Mega-Tech/` (48 files, about 29 MB in total). Games whose zips are missing are skipped.
3. Run it again only if you add more Mega-Tech zips later.

On a PC: `python3 megatech_mtc.py <MRA folder> <zip folder> <output folder>`, then copy the output folder to
`games/Mega-Tech/` on the SD card.

**Loading cartridges:**
1. Start any Mega-Tech MRA. Its game is slot 1.
2. Open the OSD (F12), go to **Cartridge Slots 2-8** and pick a `.mtc` file for each slot you want. Leave the
   others empty.
3. The menu screen now lists all loaded games. Insert coins, choose a game with **Select** (keyboard 0) and start
   it with Start, as on the cabinet.
4. Next time you start the same MRA, the same cartridges are loaded again. To change a slot, pick another file.

**Collections:** the slots and the operator settings (test menu: alarm and flash times, coin settings, bookkeeping)
are kept per MRA, not per cabinet. You can use a few MRAs as the "master" of a collection, each with its own
8 games and settings. Settings changed in the test menu are saved to the SD card the next time you open the OSD.
   Each MRA keeps its own slot list, so you can set up different line-ups under different games.

## Controls

| Cabinet | Pad (default) | Keyboard |
|---|---|---|
| Coin 1 / Coin 2 | Coin | 5 / 6 |
| Start (P1/P2) | Start | 1 / 2 |
| Select (next game; hold ~1 s on the pad) | Select | 0 |
| Enter (instruction pages) | Enter | - (minus) |
| Test (test menu) | Test | F2 |
| Service coin | | 9 |

Master System games: button 1 also starts the game.
**Test menu:** tap Test (F2) to open it, move with the joystick, hold Test ~0.5 s to open an item. Inside an item
(e.g. ALARM TIME SET) pick the row with joystick up/down and change the value with joystick left/right; Test leaves it.

## OSD extras

Screen (Game/Menu monitor), Side by Side, Coin Sound, Time Up Background (Black/Blue), Flash Warning (Dim/Shadow).

## Credits

Built on **MegaDrive_MiSTer** (Nuked-MD die-level netlists by nukeykt, MiSTer port by Alexey Melnikov / Sorgelig,
GPL-2.0+). Also uses **T80** (Daniel Wallner and contributors) for the BIOS Z80 and **jt89** (Jose Tejada / jotego,
GPL-3) for the menu PSG; the menu video chip (Mode 4 VDP) is our own, written from MAME's 315_5124.cpp. Board
behaviour from MAME's megatech.cpp, the owner's manual, decoded PAL dumps, the ElectronAsh / GadgetUK164 board
traces and RetroSix repair notes. AI-assisted; not verified on an original board.

Differences from the board: the SMS FM unit and the Mega Drive SVP chip are left out (no Mega-Tech cart uses them),
cartridge save RAM is 32 kB (no Mega-Tech cart has saves).

## Known issues

- Great Soccer is a MAME BAD_DUMP and stays on a blank screen (as in MAME).

Source: megatech/ (Quartus project MegaDrive.qpf); MRAs from tools/megatech_build.py.
