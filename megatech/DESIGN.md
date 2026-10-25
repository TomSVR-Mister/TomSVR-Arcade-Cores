# Sega Mega-Tech core: design (2026-10-23)

Target: MAME `sega/megatech.cpp` (mamedev master, copy in `ref/megatech_mame_master.cpp`).
All 48 sets there are MACHINE_NOT_WORKING in MAME: the games are ordinary console carts, the BIOS side
(menu, timer, game halt) is "preliminary". 38 sets are Mega Drive carts, 10 are SMS carts (sms_pin = FF).

## Base: MiSTer-devel/MegaDrive_MiSTer (becbdee, 2026-10-05), copied into `core/`

- It is the Nuked-MD port: die-level netlists of the real chips by nukeykt (68000, Z80, YM7101 VDP incl. SMS
  Mode 4, YM3438, I/O), GPL-2-or-later; MiSTer top level / cartridge / SDRAM by Alexey Melnikov (Sorgelig),
  GPL-2-or-later. Compatible with our GPL-3 release. Credit both (and every other author in `core/`) in the
  README when this goes public.
- The SMS mode is the real VDP's Mode 4 with the M3 pin (`cart_ms` in MegaDrive.sv), which is exactly how
  Mega-Tech runs its SMS carts. So the 10 SMS sets need no second console core.
- Rejected: JTFRAME (jotego's S18 core wraps Nuked's ym7101 inside JTFRAME, but the rest of the Mega Drive -
  68k/Z80 bus arbitration, DMA, YM3438, I/O - would have to be assembled again) and Genesis_MiSTer
  (GPL-3, older, no SMS mode).

## Mega-Tech hardware to add (from MAME, mtech_state)

BIOS side: a second Z80 (MASTER/15 = 3.58 MHz), BIOS ROM 32 kB (epr-12664.20 "ver1" default; ver0a/ver0b/
ver0aa are BIOS options), SMS-type VDP 315-5246 with its own screen and PSG (menu monitor), two CXD1095 I/O
chips.

BIOS Z80 memory map:
| range | what |
|---|---|
| 0000-2fff | BIOS ROM |
| 3000-3fff | banked RAM, 4 kB per cart slot (bank = cart select reg) |
| 4000-5fff | RAM 8 kB |
| 6000 | bank write: bank_addr = ((bank_addr >> 1) \| (d << 23)) & 0xff8000 (9 serial writes) |
| 6400-6407 | CXD1095 io1: port A in = DSW0, B in = DSW1, E out = cart select (bits 2-0) |
| 6800-6807 | CXD1095 io2: A in = IN0 (select, doors, service), B in = IN1 (coins 1-4, service coin, enter, start 1/2), C in = 0, D out (bit 7 alarm, bit 2 Genesis/SMS input disable), E in = 0, E out (bit 1 flash screen) |
| 7000-77ff | BIOS ROM |
| 8000-9fff | window into the 68000 address space at bank_addr (reads the instruction ROM at 0x300000) |

BIOS Z80 I/O: 3f ctrl write (0x55 = read A buttons), 40/41 VDP counters, 80/81 VDP data/ctrl,
dc/dd joypads (shared with the game pads), 7f PSG.

Cart image (68000 view, 4 MB): game ROM from 0, instruction ROM (epr-12368-NN, 32 kB) on the ODD bytes of
0x300000-0x30ffff. The game number NN is the cart ID the BIOS shows.

Not in MAME (no reference, work from BIOS code, say so when shipping): what the BIOS does to the game when
time runs out (MAME lets the game run; the real board holds the 68000/Z80 via the I/O ports), the alarm and
screen-flash outputs, the input-disable bit.

## BIOS I/O usage (from disassembling epr-12664.20, z80dasm; not verified on hardware)

CXD1095 registers: 0-4 = ports A-E, 6 = direction A-D, 7 = direction E. Init (0x05f0): io1 dir 0F/00,
io2 dir 3F (ports A,B in; C,D out?) / E dir 01 (bit 0 input, bits 1-3 out); io1 C,D,E = 0; io2 D = F6, E = 05.

- io1 port E (6404) bits 2-0 = cart slot (MAME: cart select), bit 3 kept.
- io2 port D (6803): bit 2 cleared when a game starts (MAME: "Genesis/SMS input ports disable"), bits 7,5,4
  cleared when the game is given time (0x0c38: and 4f) and set again when time is over (0x0ccd: or b0);
  bit 7 alone is pulsed around the instruction-ROM copy (0x0cdb/0x0d19). MAME only knows bit 7 = alarm and
  bit 2. Likely bits 4/5 hold the game CPUs (reset/halt) - to confirm (schematic or behaviour).
- io2 port E (6804): bit 1 = screen flash (MAME), bit 2 toggled by a timer routine (0x0dc6, blink?),
  bit 3 set when the game is started and cleared at time-out; after setting it the BIOS waits for
  **input bit 0 to read 0** (0x0c3d loop) = handshake from the game side. MAME returns 0 for port E.

MAME run of mt_sonic (0.264, tools: Lua write tap on :mtbios 6400-6807, see HANDOVER):
- frame 6: init as above. Frames 30-58: slot scan 7..0, each: 6404 <- slot, 6804 <- 0c, 6803 <- 46
  (= routine 0x0c1c: E bit 3 set, D bits 7/5/4 cleared, wait E bit 0 = 0, copy the instruction header,
  then 0x0cc5: D |= b0, E bit 3 cleared). Frame 62: D = f6, E = 04. Frame 80: D 66 -> f6 (0x114c path,
  clears only bits 7/4), E 0c, 08. Frame 141: E 0c. Coin 1 -> TIME 03'00" counts down; Select/Enter show
  the instruction pages. No further port writes: the game (always running in MAME) is never touched.
- So D bits 4/5 are toggled around cart accesses, not just when play starts; their exact meaning (68k/Z80
  reset or bus request, per RetroSix: "the 68k and Z80 come out of reset differently" depending on the
  game) needs the schematic. RetroSix wiki has Mega-Tech repair pages (port expander IC24, game load,
  68k, Z80 data sharing) behind a login: https://www.retrosix.wiki/port-expander-ic24-sega-mega-tech

## MRA layout (ioctl index 0, one image per set)

| offset | size | content |
|---|---|---|
| 0x000000 | 16 B | header: byte 0 bit 0 = SMS cart (MAME sms_pin FF), bit 1 = BIOS present |
| 0x000010 | 32 kB | BIOS ROM (megatech.zip, chosen BIOS) |
| 0x008010 | up to 4 MB | 68000 cart image in Mega Drive byte order, instruction ROM interleaved at 0x300001 |

Exact offsets get fixed when the loader is written; tools/megatech_build.py will read ROM_START blocks from
the MAME source (same approach as tools/<core>_build.py in the public repo) and must say MATCH against
Tom's zips. Cart ROMs use ROM_LOAD16_WORD_SWAP (MRA map swap) except mt_fwrld/mt_srbb (ROM_LOAD, already
in console order), mt_tetri/mt_calga (two byte-wide ROMs), mt_gng (ROM_CONTINUE split).

## Video

Phase 1: OSD option "Screen": Game / Menu (like Touch and Go). Both are NTSC 262-line, so a later
side-by-side or picture-in-picture view is possible via a frame buffer; check FPGA fit first.

## Phases

1. Baseline build of the unmodified MegaDrive core in the private workflow: resource use and timing.
2. MRA loading (index 0 image), Mega Drive games run with no BIOS. Builder + MATCH. First test zip.
3. BIOS Z80 + RAM + I/O + window + menu VDP; coins, timer, cart select. Sim against MAME menu screen.
4. SMS carts (M3 mode). 5. Screen modes. 6. Mega Play (megaplay.cpp), MD arcade bootlegs.

## Open questions

- Menu VDP source: SMS_MiSTer's vdp.vhd (port of Ben's Papilio SMS) has no licence file; do not copy it
  until that is settled. Alternatives: write a 315-5246 Mode 4 renderer ourselves (MAME 315_5124.cpp as
  reference), or check other GPL SMS cores.
- FPGA space: Nuked-MD is a large netlist core; phase 1 tells how much room is left.
- Simulation: no MAME binary in the container yet; install MAME (or build) before phase 2 verification.

## ElectronAsh / GadgetUK164 partial KiCad board (Tom, 2026-10-23; nets traced from the .kicad_pcb)

Partial: only IC13-IC15, IC17 (SMS Z80), IC21-23, IC30/31 (PALs), IC33/34, IC37-42, IC48-50, IC52-54 (68k),
IC56 (MD Z80), IC70 and the 8 slots. The menu VDP (IC16), IC24 and IC7 have no pads, so the SMS Z80 INT/WAIT/
NMI nets end at the Z80: **the interrupt source of the menu Z80 is NOT resolved by this file.**
- MD Z80 /RESET = IC21 OR(IC23 inverter(IC24 **PD4**), 315-5308 ZRES) -> PD4 = 0 releases the MD Z80
  regardless of the 5308 (RetroSix said D5; the board file says PD4, pin 24).
- PAL IC14 (AM16L8) decodes the SMS Z80: inputs A10-A15, MREQ, IORQ, RFSH, IC24 **PD7**; outputs SMS ROM /CE,
  VDP IORQ, /CS IC7, /CS IC24, SMS NVRAM (IC27 pin 20, battery RAM = bookkeeping), SMS Z80 RD enable, and
  GEN_Z80_CONT_EN (enables IC15: the SMS Z80 drives the MD Z80 control lines = the 8000-9fff window / 6000
  bank register are the MD Z80's own map, borrowed by the menu Z80).
- PAL IC31 pin 11 = 68k /RESET (from 5308 pin 20 per the net name); IC30 pin 16 = IC13/IC33/IC34 /G (bus
  buffers between the two Z80 buses).

## Arcade Otaku pinout (Tom, 2026-10-23)
CN2 (Select): 1 Select, 5/6 Door SW 1/2, 8 Test, 9-12 coin A.1-A.4, 13 Service, 14 Enter, 18 Coin Meter (out),
25 Com A. CN1 (Lamp): I.1-I.4. CN4/CN7: Up, Down, Left, Right, Shot 1-3, Start (3-button pads). CN5 gun
connector exists but no gun games were released. CN8 = main monitor, CN9 = menu monitor.
Core: our "Service" button drives io2 port A bit 7 = CN2 Test (test mode) -> renamed "Test" (OSD/MRA).

## Official owner's manual (Sega Mega-Tech Owners Manual, Edition 1.0, 420-5901; Tom 2026-10-23)
"How to operate": attract mode = demo on the main monitor (20"), game instructions on the sub-monitor (10");
Enter = next instruction page and the 1-8 menu; coin starts the countdown (credit buys time); Select picks
the game, START begins it; "warned near the end of the time limit by on-screen flashes and audible alarms";
"When the time is up, 'TIME UP' will be displayed on the screen"; coin any time extends the time;
"After play is finished, the game returns to the attract mode". Test menu: Output test (ALARM, FLASH),
Alarm time set (ALARM 0-30 s, FLASH 0-30 s; example 15 s / 10 s). FLASH = io2 port E bit 1 (MAME
Flash_screen) -> on-screen flash not implemented yet.

## PLD dumps (Tom, 2026-10-23): docs/research/plds (jedutil -view <jed> GAL16V8)
315-5346 = IC14 (pins from the KiCad board: 1-6 A10-A15, 7 /MREQ, 8 /IORQ, 9 /RFSH, 11 IC24 PD7;
outputs 12 /SMS_ROM_CE, 13 /RD_EN, 14 /VDP_IOREQ, 15 /CS IC7, 16 /CS IC24, 17 ?, 18 /GEN_Z80_CONT_EN,
19 /NVRAM). Decoded:
- ROM: 0000-2FFF and 7000-77FF (MREQ, not refresh). 3000-3FFF -> /RD_EN (read through IC13 from the
  MD side). NVRAM (battery, IC27): 4000-5FFF. IC7 (io1): 6400-67FF. IC24 (io2): 6800-6BFF.
  **6C00-6FFF -> pin 17 (unknown device; the BIOS reads 6C00 at 0x061a)**.
- Menu VDP I/O only when **PD7 = 1**. When **PD7 = 0**: every I/O cycle, 8000-FFFF, 6000-63FF and 7C00-7FFF
  go to the MD Z80 bus (GEN_Z80_CONT_EN): the menu Z80 then drives the MD Z80's bus (bank register at 6000,
  68k window at 8000, MD VDP/PSG/YM ports).
315-5347B (IC31, 68k reset logic), 315-5348A (IC30, bus buffer enables), 315-5349A, 315-5356: decoded,
pin maps not known (partial board file).
