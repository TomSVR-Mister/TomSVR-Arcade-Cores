# TomSVR_snesb: SNES arcade bootlegs for MiSTer

Unofficial MiSTer core for the arcade bootleg boards that run hacked Super Nintendo games (MAME driver
`nintendo/snesb.cpp`), released as TomSVR_snesb. 15 MRAs:

| Game | MAME set |
|---|---|
| Killer Instinct | kinstb |
| Final Fight 2 | ffight2b |
| Final Fight 3 (set 1, set 2) | ffight3b, ffight3b2 |
| Iron (bootleg of Iron Commando) | iron |
| Ghost Chaser Densei (set 1, set 2) | denseib, denseib2 |
| Gundam Wing - Endless Duel (set 1, set 2) | endless, endlessa |
| Legend | legendsb |
| Rushing Beat Shura | rushbets |
| Sonic Blast Man II Special Turbo | sblast2b |
| Teenage Mutant Ninja Turtles - Mutant Warriors | tmntmwb |
| Venom & Spider-Man - Separation Anxiety | venom |
| Wild Guns | wldgunsb |

Each board is a SNES chipset plus a programmable logic chip that scrambles the ROMs, reads the coin mechanism and DIP
switches, and answers the game's protection checks. The games themselves run on SNES_MiSTer.

## What the board side does

- **ROM descrambling while loading** (`rtl/sb_load.sv`): the MRA sends the ROMs exactly as they are in your MAME zips.
  The core undoes each board's scramble (data bits swapped and inverted per 64 KB bank, and on most boards also the
  address lines and a nibble substitution) while it writes them to SDRAM. For every set the result is byte for byte
  the ROM MAME decrypts.
- **Board I/O and protection** (`rtl/sb_board.sv`): DIP switches and coin inputs where the games read them
  (77:0071 / 0073 / 0079), the fixed values the protection checks expect, a read counter, small RAMs the games
  share with the logic chip, and the reset values some games need (Wild Guns' continue counter, Final Fight 2's
  credits). All of it comes from the MRA, so one core runs every board.
- **Mapping**: LoROM or HiROM is forced per game, as on the boards (the bootleg ROMs don't carry a usable header).

## Controls and settings

- Coin is on the pad's **Select** button by default; the SNES Select button moves to **R2**. Start is Start.
- The DIP switches (coinage, difficulty, lives ...) are in the OSD.

## Notes

- **Legend**: MAME marks one of its ROMs as a bad dump (combined from several bad dumps).
- **Final Fight 3**: MAME does not emulate its protection and patches it out of the game code; this core applies the
  same patch.
- Not in this release: International Superstar Soccer Deluxe (still being fixed), Pirates of Dark Water (its board
  adds a 68000), and the boards with an 8051 overlay (Mortal Kombat 3, Killer Instinct with overlay, the 4-slot
  switchers, MAME `snesb51.cpp`).

## Credits

- **srg320 and the MiSTer-devel contributors**: [SNES_MiSTer](https://github.com/MiSTer-devel/SNES_MiSTer) (GPL-3),
  which runs the games (see `UPSTREAM.txt` for the imported version).
- **Tomasz Slanina, Peter Ferrie and Stephane Humbert**: MAME's `snesb.cpp` (BSD-3-Clause), which documents the
  boards' scrambling and protection.
- MRAs are made by `tools/snesb_build.py` from MAME's driver source.
