# TomSVR_megatech: Sega Mega-Tech for MiSTer

Unofficial MiSTer core for the Sega Mega-Tech arcade system (MAME driver `sega/megatech.cpp`), released as
TomSVR_megatech. One cartridge per MRA; the cabinet's menu screen, coin timer, TIME UP, alarm and flash
warning are run by the real Mega-Tech BIOS.

Built on **MegaDrive_MiSTer** (Nuked-MD die-level netlists by nukeykt, MiSTer port by Alexey Melnikov / Sorgelig,
GPL-2.0+). Also uses **T80** (Daniel Wallner and contributors) for the BIOS Z80 and **jt89** (Jose Tejada / jotego,
GPL-3) for the menu PSG. Board behaviour from MAME's megatech.cpp, the owner's manual, decoded PAL dumps and
RetroSix repair notes. AI-assisted; not verified on an original board.

OSD extras: Screen (Game/Menu monitor), Coin Sound, Time Up Background, Flash Warning (Dim/Shadow).
Inputs: A, B, C, Start, plus Coin, Select (hold ~1 s = next/restart, as the cabinet's Select), Enter, Test.

Known issues (2026-10-25): Out Run and Parlour Games (SMS based) show missing sprites; Great Soccer is a
MAME BAD_DUMP and stays on a blank screen (as in MAME); NVRAM (test-menu settings, bookkeeping) is not saved.
2026-10-25: TIME UP is clean (the BIOS now resets only the game CPUs, as on the board, so the video never
loses sync; the screen stays black until the restarted game turns its display on).

Source: megatech/ (Quartus project MegaDrive.qpf); MRAs from tools/megatech_build.py.
