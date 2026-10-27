# TomSVR_megaplay: Sega Mega Play for MiSTer

Unofficial MiSTer core for the Sega Mega Play arcade board (MAME driver `sega/megaplay.cpp`). It is built from the same
source as the TomSVR Mega-Tech core (`megatech/`, Quartus project `MegaPlay.qpf`), with the Mega Drive game side running
on MegaDrive_MiSTer (Nuked-MD) and the Mega Play BIOS board around it.

## What works

- The real Mega Play BIOS runs the cabinet: attract screens and instructions drawn over the game picture, credits,
  coin settings, game over and continue.
- All 12 Mega Play sets in MAME, one MRA each (the MRA's game sits in slot 1). Bio-hazard Battle is marked not
  working in MAME and plays here.
- **The 4-slot board**: slots 2-4 are filled from the OSD ("Cartridge Slots 2-4") with `.mpc` cartridge files. With
  a credit in, Select (hold it about 1 second on a pad) cycles the games on the menu, Start plays the one shown.
  Loading a cartridge restarts the board, which starts on slot 1, as on the real cabinet.

## Making the .mpc files

An MRA can only build its own cartridge from your MAME zips, so slots 2-4 use ready-made cartridge files:

1. If you use update_all with this repository's db, the scripts are already in `/media/fat/Scripts/`. Otherwise
   copy `tools/megatech_mtc.py` and `tools/megatech_make_mtc.sh` there.
2. Run `megatech_make_mtc` from the Scripts menu. It reads the TomSVR Mega Play MRAs in `_Arcade` and your zips in
   `games/mame`, and writes `games/Mega Play/<game>.mpc` (and Mega-Tech `.mtc` files to `games/Mega-Tech`).

The files are your own ROMs; don't share them. A `.mpc` has the MRA image layout with the BIOS part left empty, and
header byte 2 holds the game's DIP switch nibble (the MRA default).

## How the 4-slot board is modelled

MAME only has the 1-slot board, so the 4-slot behaviour is worked out from what the BIOS code expects:
the slot select (I/O port D bits 1-0) picks the cartridge for the game side and for the BIOS window, 6600 bit 0
reads back the slot select bit (the BIOS's board check), 6402 bits 3-0 are the cartridge-present lines, the DIP
switches of slots 2-4 are read at 6201/6202, and the RAM at 4000-5fff is banked per slot (the BIOS copies each
game's instruction ROM there and runs code from it). Any filled slot 2-4 turns the core into the 4-slot board.

## Credits

MAME `sega/megaplay.cpp` (BSD-3-Clause, David Haywood) and `cxd1095.cpp` (AJR) for the board's map and I/O;
Nuked-MD (nukeykt) and MegaDrive_MiSTer (Alexey Melnikov / Sorgelig), GPL-2.0-or-later; jt89 (jotego) for the
overlay PSG, T80 for the BIOS Z80. Board facts from the service manual and PLD dumps shared by the community.
