# JTGAELCO2: where the code comes from

JTGAELCO2 runs the Gaelco 2 boards of MAME's `gaelco2.cpp` (Maniac Square first). It is built on **JTFRAME** by
Jose Tejada (jotego). The Gaelco 2 video pipeline and the GAE1 sound chip come from **jlrh's gaelco-fpga**
(https://github.com/jlrh/gaelco-fpga, GPLv3, Alligator Hunt core, commit 85fe58b). Behaviour is checked against
MAME 0.264/0.288.

## What comes from where

| Part | Source | Files |
|---|---|---|
| 68000 CPU, bus timing (DTACK), IRQ | JTFRAME (jtframe_m68k with fx68k, jtframe_68kdtack_cen, jtframe_edge) | `jtgaelco2_main.v` (ours, after our JTWRALLY / jotego's JTGAE1) |
| Address decoder, inputs, DIPs, video registers | ours, from MAME `maniacsq_map` | `jtgaelco2_main.v` |
| Work RAM, shared RAM, VRAM, palette | JTFRAME `jtframe_ram16`, `jtframe_dual_ram16` | `jtgaelco2_vmem.v`, `jtgaelco2_game.v` (ours) |
| SDRAM, ROM download, header, video output, OSD, scaler | JTFRAME | generated |
| Per-game header (plane size, plane limit, sound banks), MRAs | ours | `jtgaelco2_game.v`, `tools/gaelco2_build.py` |
| Video timing, tilemaps, sprites, palette decode, layer mixing | jlrh | `aligator_video_top.v`, `aligator_video_timing.v`, `aligator_gae1_video.v`, `aligator_gae1_tilemap.v`, `aligator_gae1_sprite.v`, `aligator_gae1_palette.v` |
| GAE1 sound | jlrh | `aligator_gae1_sound.v` |

Size (lines of Verilog in `hdl/`, 2026-10-22): jlrh's files 917, ours 484; everything else is JTFRAME.

Not used from jlrh's Alligator Hunt core: its game top, 68000 bus and address decoder, its own copy of fx68k, its
DTACK module, its inputs, its VRAM module (five full VRAM copies), its DS5002FP wrapper and 8051 (`mc8051_regen`),
its copy of `jtframe_ram_rst`, its timing constraints for the 8051, and the post-generation patch script its build
needs. The protected sets will use our own DS5002FP on jt8051 (from our JTWRALLY).

## Changes made to jlrh's files

| File | Change | Why |
|---|---|---|
| `aligator_gae1_sound.v` | Volume table computed in place with MAME's formula | the original reads `volume_table.mem`, which is not in the jlrh repository |
| `aligator_gae1_sound.v` | `bank_map` input: sound bank -> graphics plane | Alligator Hunt's bank offsets were fixed; other games use other offsets (MAME `set_bank_offsets`) |
| `aligator_gae1_tilemap.v` | Line buffer reads registered | combinational reads made Quartus build the buffers from ~24k registers; the design did not fit |
| `syn/timing.sdc` | Only the 48/96 MHz clock-crossing lines kept | the rest constrained the 8051 we do not use |

Not jlrh's, but noted here: `hdl/jt8051_regs.v` is jotego's jt8051 file with one fix (bug 10).

## Bugs and differences found

| # | Where | Found | Status |
|---|---|---|---|
| 1 | jlrh sound: `volume_table.mem` missing from the repository | 2026-10-22, reading the code | fixed (computed from MAME) |
| 2 | jlrh tilemap: line buffers not mappable to block RAM | 2026-10-22, first Quartus build (77k logic cells, did not fit) | fixed |
| 3 | jlrh sprites read live sprite RAM; MAME draws from a copy buffered at vblank | 2026-10-22, reading the code; confirmed on Snow Board (spinning globe one animation step early) once the comparison used every MAME frame | fixed: VRAM copied to the sprite engine at vblank |
| 4 | With JTFRAME_SDRAM_LARGE the sim fetched the 68000 program from twice the address | 2026-10-22, sim (line-F trap at boot) | ours, sim only: tools/gen_sim.sh wrote the SDRAM files linearly, but the 64 MB controller puts address bit 22 in the column; fixed (LARGE=1), LARGE back on |
| 5 | Ours: SDC file lost its closing brace when trimmed | 2026-10-22, first build | fixed |
| 6 | Fades looked one step off vs MAME | 2026-10-22, sim vs MAME | not a bug: my comparison was one frame misaligned; sim frames 180-470 are pixel-identical to MAME frame for frame |
| 7 | Ours: MRA button list had "-" for unused buttons; MiSTer shifted the default mapping (coin and start on face buttons) | 2026-10-22, Tom's hardware test | fixed in the MRAs |
| 8 | jlrh video: line-scroll table indexed by screen line; MAME indexes it by tilemap row (screen line + vertical scroll) | 2026-10-22, reading MAME while chasing a Snow Board difference | fixed (that difference turned out to be #3) |
| 9 | Snow Board globe: on one frame in three the sim shows the next animation step one frame before MAME | 2026-10-22, every-frame comparison | open, cosmetic: the CPU's sprite write lands just before vblank in the sim and just after it in MAME (MAME's vblank timing is marked not accurate) |
| 10 | **jotego's jt8051** (jtcores bfced64): bit instructions on ACC, B, PSW (and SP/DPTR writes via the same path) load the bit value instead of the modified byte (`src` instead of `sfr_din`), so SETB ACC.7 gives 01, not 80 | 2026-10-22, protected Maniac Square: matched blocks never cleared (Tom's HW test); found by diffing the DS5002FP's shared-RAM accesses against MAME | fixed in our copy `hdl/jt8051_regs.v`; sim now = MAME pixel for pixel through the first matches (frame 1760). Also affects our wrally, sqix, semicom cores if their MCU code uses such bit ops |
| 11 | Ours: MRA tool did not pad between the end of planes 1-4 and the plane-5 start (0x1100000); only Snow Board (4 MB planes) fills that gap exactly, so on Bang! plane 5 loaded at the wrong address (32-step ramps showed as two 16-step ramps, text missing) | 2026-10-22, Bang! sim vs MAME test screen | fixed in tools/gaelco2_build.py; only the Bang! images change |
| 12 | Ours: pxl_cen was made in the 48 MHz domain but JTFRAME uses it at 96 MHz, so each pulse counted twice there: the light-gun overlay drew every aim point twice (~256 px apart) and neither sat on the real aim point, so Bang! shots never hit | 2026-10-22, Tom's hardware test of Bang! | fixed: one-clock pulses on clk (96 MHz) for JTFRAME, the 48 MHz enable kept for our video |
| 13 | Ours: Bang! got 9 gun interrupts per frame (MAME 7): a pulse at vblank plus one more where the 33-line counter met the frame end; the game stores one sample per interrupt in a 7-entry table, so the overrun broke hit detection | 2026-10-22, Tom's hardware test (shots heard, never hit); sim vs MAME per-frame log of the game's sample counters | fixed: 7 pulses at 1/8..7/8 of the frame after vblank, as MAME |
| 14 | Ours (touchgo branch): the DS5002FP internal RAM became a jtframe_ram (for the scratch preload); jt8051's timing.sdc names jtframe_ram_rst:u_ramu, so its two-clock paths lost their multicycle and the build missed timing by ~2 ns | 2026-10-22, CI build of the touchgo branch | fixed: the same multicycle for jtframe_ram:u_ramu in syn/timing.sdc |
