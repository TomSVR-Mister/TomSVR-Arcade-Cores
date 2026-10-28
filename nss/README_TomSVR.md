# TomSVR_nss: Nintendo Super System for MiSTer

Unofficial MiSTer core for Nintendo's Super System arcade cabinet (1991, MAME driver `nintendo/nss.cpp`), released
as TomSVR_nss. One cartridge per MRA: 12 MRAs, one for each NSS game MAME has fully dumped.

The original NSS BIOS runs the cabinet, so you get the arcade experience: the boot screens, the attract mode
("You Are Now Viewing ..."), the game menu, credits, the time limit per credit with its on-screen counter, and
"Deposit coin to continue". In MAME 0.264 (status: preliminary) 5 of these 12 games (Contra III, Robocop 3, Super Mario
World, Super Soccer, Super Tennis) stop at "NON SLOT", and none of them draws the OSD over the game; here all 12 play.

## What works

- **The real BIOS** (nss-ic14.02, the single-cartridge BIOS) checks the cartridge, shows the menu and runs the coin
  and time logic. Settings (coinage, time per credit, free play) are stored in the board's EEPROM and saved to the
  SD card.
- **The cartridge security chip** (RP5H01 PROM): the BIOS decrypts each cartridge's instruction ROM with it. It has to
  be read least significant bit first with inverted data. MAME reads it the other way round, which only some
  cartridges survive (the other 5 show NON SLOT). Found by stepping the BIOS's cartridge check.
- **The on-screen display chip** (Mitsubishi M50458) is drawn **over the game picture**, as on the cabinet: the
  timer and credits in game, the menus and attract text, with the black outline round every character and the
  per-character colours. MAME shows it on a separate screen. Character size per row, scrolling and the raster colour
  follow the chip's registers; the boot screen and game menu match photos of real machines.
- **The SNES side** is SNES_MiSTer, controlled by the BIOS as on the board: held in reset until a game is paid for,
  paused while waiting for a coin to continue, joypads cut off in attract mode, sound mute, the cartridge DIP
  switches at 4100h and the game-over line (4016h bit 2).
- Cabinet buttons on the pad: Coin is on Select by default (the SNES Select button moves to R2), Instructions on L2.
  Game 1-3, Page Up/Down, Service and Restart can be mapped in the MiSTer menu.

## Games

ActRaiser, The Addams Family, David Crane's Amazing Tennis, Contra III, F-Zero, Lethal Weapon, NCAA Basketball,
Robocop 3, The Irem Skins Game, Super Mario World, Super Soccer, Super Tennis.

Not included: **Super Mario All-Stars**. Its security PROM has never been dumped (MAME: NO_DUMP, and its game ROMs
are marked BAD_DUMP), so the BIOS rejects the cartridge.

## ROMs

MAME zips in `games/mame`: `nss.zip` (BIOS), `m50458.zip` (the OSD chip's character ROM) and the game's zip
(`nss_smw.zip`, ...). Nothing is modified; the MRA assembles the image from your files.

## Notes and differences

- **Watchdog:** the board can drop a cartridge whose SNES stops reading its joypads (the BIOS then shows NON SLOT and
  refunds the credits). What exactly clears that flag on the real board is not known; reading it as the joypad latch
  made Lethal Weapon and NCAA Basketball trip it during their intros, so it is cleared every frame, as in MAME
  (both play on MiSTer now).
- **Timer:** the counter shows for the first seconds of play and again near the end. This is the BIOS's own logic
  (real-machine videos show the same), not a bug.
- The picture is sent at one pixel per SNES master clock (1024 pixels per line) so the OSD's dots, which are
  smaller than the SNES's, land on whole pixels.
- The SNES cartridge coprocessors (SuperFX, SA-1, ...), MSU-1 and save states of SNES_MiSTer are left out: no NSS
  game uses them, and the board needs the room.

## Known issue

- Now and then a game shows a **black screen on its first start** (seen with Robocop 3); loading the MRA again
  works. Being worked on.

## How it was built

- **Starting point:** SNES_MiSTer (GPL-3) for the game side, the T80 Z80 (Daniel Wallner) for the BIOS CPU.
- **The board:** nocash's fullsnes NSS chapters (memory and I/O map, EEPROM and PROM formats, the OSD chip's
  registers), DogP's NSS page and the nesdev NSS thread, the M50458 datasheet, and MAME's nss.cpp,
  m50458.cpp, rp5h01.cpp, m6m80011ap.cpp and s3520cf.cpp for the details.
- **The BIOS as the judge:** the cartridge check, the EEPROM bit timing and the OSD layout were worked out by running
  the original BIOS in a Z80 model and a Verilator simulation of the board, and reading its code where it differs
  from the documents. The simulated boot screen and game menu were compared with photos and video of real cabinets.
- **MRAs** are generated from MAME's -listxml by tools/nss_build.py.

## Credits

SNES_MiSTer (srg320 and the MiSTer-devel contributors), T80 (Daniel Wallner), nocash (Martin Korth) for fullsnes,
DogP for his NSS research, the MAME team (Angelo Salese and others) for nss.cpp and the chip devices.
TomSVR core work: Tom, with Claude (Anthropic).

## License

GPL-3.0 (as SNES_MiSTer). The T80 keeps its own BSD-style license (see the file headers).
