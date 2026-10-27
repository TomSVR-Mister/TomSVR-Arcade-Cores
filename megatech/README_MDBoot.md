# TomSVR_mdboot: Mega Drive arcade bootlegs for MiSTer

Unofficial MiSTer core for the arcade bootleg boards that run Mega Drive games (MAME driver
`sega/megadriv_acbl.cpp`). It is built from the same source as the TomSVR Mega-Tech core (`megatech/`, Quartus project
`MDBoot.qpf`, `define MDBOOT`): the Mega Drive side runs on MegaDrive_MiSTer (Nuked-MD), and `rtl/mdb_io.sv` adds
each board's coin and DIP switch ports and protection.

## Games

All 16 working sets in MAME, one MRA each (MAME zip names, merged parent zips work):

| Set | Game | Board |
|---|---|---|
| aladmdb | Aladdin | PIC16C57 protection |
| barek2mb | Bare Knuckle II | PIC16C57 protection |
| jparkmb | Jurassic Park | PIC16C57 protection |
| sonic2mb | Sonic The Hedgehog 2 | own I/O and RAM |
| barekch, barek2ch, barek3mb, biohzdmb, mk3mdb, srmdb, ssf2mdb | Bare Knuckle I/II/III, Bio-Hazard Battle, Mortal Kombat 3, Sunset Riders, Super Street Fighter II | scrambled ROMs |
| barek3mbc, contrambc, sidepmbc, mickeycmb | Bare Knuckle III, Contra, Side Pocket, The Great Hongyun Shu 1996 | Conny |
| 3in1mbc | Gunstar Heroes / Snake Rattle n' Roll / Joe & Mac | Conny 3-in-1 |

- Coin is the pad's Select, Start is Start (MRA button defaults, no mapping needed). Keyboard 5/6 = coin.
- Mortal Kombat 3, Super Street Fighter II and the scrambled Bare Knuckle use a 6-button pad, laid out as in the
  MiSTer Genesis core (C on R, Z on L). Pads whose C/Z buttons MiSTer doesn't map automatically (such as the
  8BitDo M30) need one "Define joystick buttons" in the MiSTer main menu.
- 3-in-1: press A during the attract mode (no credits) to switch games.
- DIP switches are in the OSD.

## How it works

The MRA sends one image: a 16-byte header (board family, descramble scheme, protection values, pad flags), the PIC
program at 0x1000 and the 68000 ROM from 0x10000. The scrambled sets are unscrambled while loading, with the same
bit swaps as MAME's `init_*` functions (checked byte for byte against MAME for five sets). The PIC16C57 is
`playmark/hdl/jtplaymark_pic.v`. The Conny boards' coin raises an NMI on press and release, as MAME notes. The 3-in-1
board banks 000000-0fffff in 1 MB pages; the bank follows address lines A21-A20 only, because the cartridge never
sees A22/A23 (Gunstar Heroes' sprite DMA drives A23 high).

## Credits

MAME `sega/megadriv_acbl.cpp` (BSD-3-Clause, David Haywood, Stephane Humbert) for the board maps, descrambling and
protection; Nuked-MD (nukeykt) and MegaDrive_MiSTer (Alexey Melnikov / Sorgelig), GPL-2.0-or-later.
