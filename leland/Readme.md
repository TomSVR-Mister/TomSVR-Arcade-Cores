# Leland - MiSTer FPGA Core

MiSTer core for the Cinematronics / Leland Cinemat System arcade hardware, as
used by Leland Corp. games: twin Z80 master/slave boards, tile and sprite video,
and the 80186-based sound board, all in RTL.

## Supported games

| Game | MAME set | MRA |
|---|---|---|
| Ironman Ivan Stewart's Super Off-Road (rev 4) | `offroad` | `Ironman Ivan Stewart's Super Off-Road (rev 4).mra` |
| Ironman Ivan Stewart's Super Off-Road Track-Pak (rev 4) | `offroadt` | `Ironman Ivan Stewart's Super Off-Road Track-Pak (rev 4).mra` |
| Pig Out: Dine Like a Swine! (rev 2?) | `pigout` | `Pig Out Dine Like a Swine! (rev 2).mra` |
| Ataxx (rev 5) | `ataxx` | `Ataxx (rev 5).mra` |
| Danny Sullivan's Indy Heat (rev 1) | `indyheat` | `Danny Sullivan's Indy Heat (rev 1).mra` |
| Brute Force | `brutforc` | `Brute Force.mra` |

All six are playable with sound. Other Leland boards are not supported.

The core was written from MAME's Leland drivers and the game ROMs, and has
not been checked against an original PCB.

## Video

Analog (15 kHz RGB and Y/C) and HDMI output both work.

| OSD option | Effect |
|---|---|
| Aspect ratio | Original, Full Screen or a custom ratio |
| Video Timing | **CRT 60Hz** (default): a DDR3 frame buffer re-times the picture to NTSC-standard 240p (15.73 kHz, 60.03 Hz) while the game runs at its native 65.95 Hz. **Native 66Hz**: the game's own timing is output unchanged. |
| CRT V Position | Moves the picture up or down (CRT 60Hz only) |
| CRT V Size | Scales the 240-line picture down to 236 ... 208 lines with a vertical blend done in linear light, for CRTs that overscan top and bottom (CRT 60Hz only) |

## Controls

Steering comes from three sources that are added together, so they can be mixed:

| Input | Behavior |
|---|---|
| Spinner | 1:1, like the cabinet's wheel |
| Analog stick | Deflection sets the turn rate |
| D-pad | Left/Right steer. **D-Pad Steering** selects **Velocity** (default: ramps a turn rate and coasts back to straight) or **Position** (a virtual spring-centered stick) |

Buttons are listed per game as player controls, then coin, then start, and a game only lists the
buttons it uses, so the OSD mapping never asks for an unused one. Each MRA carries its own names:

| Game | Buttons, in mapping order |
|---|---|
| Super Off-Road / Track-Pak | Gas (digital: off or full), Nitro, Menu Enter (see Service menu), Coin |
| Indy Heat | Gas (digital), Nitro, Menu Enter (see Service menu), Coin |
| Pig Out | Jump, Throw, Coin, Start |
| Brute Force | Punch/Kick, Dive, Menu Enter (see Service menu), Coin, Start (three players, controllers 1 to 3) |
| Ataxx | Place, Coin, Start |

After updating from an earlier release, re-run **Define joystick buttons** in the OSD: the order
changed for every game.

## Service menu

Choose **Service Menu** in the OSD to open the operator menu. The core presses
Test for you (plus P1 Start for Pig Out and Brute Force). In the Super Off-Road and
Indy Heat menus, **Menu Enter** acts as Blue Nitro (P3 Nitro), so one controller can
select with Nitro and enter with Menu Enter. In the Brute Force menu, P1 Start moves to
the next item and **Menu Enter** acts as P3 Start to choose it. Lives and difficulty are
set here; the hardware has no DIP switches.

Operator settings and bookkeeping (the game's EEPROM) are saved to the SD card as
`/media/fat/config/nvram/<MRA name>.nvm` when you open the OSD after the game has changed
them, and are restored the next time the game loads. Delete the `.nvm` file to return to the
defaults. The MRAs must include the `<nvram index="4" size="128"/>` line.

## Known issues

- The first **Service Menu** selection after loading the core does not open the menu in
  any of the three games. Later attempts work. It looks like a timing race, and a second
  selection is the workaround.
- Pig Out and Brute Force can still show a few wrong background pixels (up to about 30,
  one scanline high) at the left edge of the top of the status panel at the bottom of the
  screen, where the game changes scroll in the middle of the picture. A longer line there
  is fixed. The rest follows the game's own scroll-write timing against the raster, and
  it is not known whether an original board shows it (see `sim/BRUTE_FORCE_HUD_TIMING.md`).

## Installing

Copy to your MiSTer:

- `releases/Arcade-Leland_<date>.rbf` to `/media/fat/_Arcade/cores/`
- the MRA for each game you want, from `releases/`, to `/media/fat/_Arcade/`

You need the MAME 0.257 ROM zip for each game (`offroad`, `offroadt`,
`pigout`, `ataxx`, `indyheat`, `brutforc`). No ROM data is included in this repo.

The MRAs load ROMs through DDR3 (`address="0x30000000"`), which is much
faster than the per-byte download.

## Building

Requires Quartus Prime 17.0.x. The Z80 core and the YM2151 core are submodules:

```sh
git clone --recurse-submodules https://github.com/shimian5/Arcade-Leland_MiSTer
cd Arcade-Leland_MiSTer
quartus_sh --flow compile Leland
```

The result is `output_files/Leland.rbf`.

## Simulation

`sim/` has ModelSim and Verilator testbenches for the SDRAM controller, the
sound board and the full board. See `sim/README.md`.

## Credits

- MAME's `leland.cpp`, `leland_m.cpp`, `leland_v.cpp` and `leland_a.cpp`, used
  as reference (not redistributed).
- [tv80](https://github.com/hutch31/tv80): Z80 core (MIT), submodule in `rtl/tv80`.
- [jotego/jt51](https://github.com/jotego/jt51): YM2151 core for the Indy Heat sound
  board (GPLv3), submodule in `rtl/jt51`.
- [jamieiles/80x86](rtl/s80x86/README_VENDORING.md): 8086/80186 core for the
  sound CPU (GPLv3), vendored.
- [KF8253](rtl/KF8253/README_UPSTREAM.md): 8253 PIT core.
- `rtl/mem/sdram.sv`, `rtl/mem/sdram_banked.sv`: SDRAM controllers (MIT, Kevin Coleman).
- The [MiSTer framework](https://github.com/MiSTer-devel) in `sys/`.

## License

GPL v3 or later, see `LICENSE`. Vendored and third-party components keep their
own licenses.
