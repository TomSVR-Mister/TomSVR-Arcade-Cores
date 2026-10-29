# Pig Out / Brute Force HUD line: root cause

Investigated 2026-10-02 on the Brute Force branch at `ef2bc86`. The investigation itself
changed no RTL; the fix is described under "Fix" below. The supplied captures were from HDMI
at 720p60.

## Finding

The background tile prefetch queue retains data fetched with the world scroll
coordinates across the switch to the lower HUD's scroll coordinates. The display
consumes those entries after the scroll registers change, so a short strip uses
the wrong background tile/row. Both titles exercise this same path despite using
different background formats: Pig Out uses the PROM tilemap, Brute Force uses QRAM.

The relevant code is `rtl/video/leland_video.sv`:

- Lines 115–117 use the scroll registers live.
- Lines 195–226 define the eight-entry tile-row queue. Entries contain plane data
  and colour, without scroll/position tags that the consumer could validate.
- Lines 318–331 compute fetch targets using the current scroll.
- Lines 444–448 mark a row resynchronization, which adjusts future producer targets
  but does not invalidate already queued data.
- Lines 450–460 arm new fetches. Lines 463–476 consume the existing queue.
- The queue is cleared on reset, but no scroll-change invalidation exists.

Brute Force also changes X scroll during active pixels on the first HUD row.
That is a separate contribution to the same seam: live scroll application differs
from MAME's scanline rendering. Correcting queued provenance alone leaves a shorter
31-pixel timing seam in the captured replay. A future fix must consider both the
prefetch lifetime and the split's raster timing; simply clearing the queue has not
been evaluated as a fix.

## Evidence

MAME's local `leland_v.cpp` calls `update_partial(vpos()-1)` before `scroll_w`
updates the register. It renders the current scanline with the new scroll.
This establishes the reference rendering convention, not a measurement of an
original PCB's latch timing.

Actual gameplay writes captured from the user's local ROM sets:

| Title / captured frame | Beam (y,x) | Port/data | Effect |
|---|---|---|---|
| Brute Force / 600 | (207,395) | F3=03 | Y high byte |
| Brute Force / 600 | (207,417) | F2=10 | HUD Y=0310 |
| Brute Force / 600 | (208,11) | F0=00 | X low byte |
| Brute Force / 600 | (208,24) | F1=00 | HUD X=0000 |
| Pig Out / 850 | (216,248) | 4D=00 | X high byte |
| Pig Out / 850 | (216,266) | 4C=00 | HUD X=0000 |
| Pig Out / 850 | (216,303) | 4F=06 | HUD Y high byte |
| Pig Out / 850 | (216,321) | 4E=00 | HUD Y=0600 |

Brute Force's captured world scroll is X=0530, Y=0268. Pig Out's captured first
scene uses X=0000, Y=0000 and gfxbank=07. Its HUD switch arrives late on line 216,
after some tiles for line 217 have already been fetched. This places the visible
pink strip on line 217, exactly above the Oscar panel.

The full board simulation, including the 80186 and SDRAM controller, independently
showed stale queued entries. For example, Brute Force frame 44 changed Y at
(207,397) and (207,419), with eight entries already queued for line 208. Pops at
X=0,8,...,56 returned tile row 26 from the previous scroll, while the live scroll
required row 124. The trace reports `bad=8 under=0` for that frame: populated but
incorrect entries, rather than a queue underrun. These long runs were stopped after
frames 263 / 268 once the replay isolated the cause; they did not complete the
configured seven-second run or reproduce Pig Out gameplay through its initials menu.

The short replay uses the **unchanged** `leland_video.sv`, its exact fractional
pixel enable, actual graphics ROM/PROM bytes, captured foreground/palette/QRAM, and
the recorded scroll-write positions. It reproduces Pig Out's pink line and Brute
Force's seam at the left HUD boundary. The particular Brute Force snapshot produces
grey world pixels at this seam; the supplied captures show black. The erroneous
pixels come from the world background and therefore their colour depends on the
scene and palette.

Three simulation modes distinguish cause from correlation:

- Mode 0: original RTL behavior.
- Mode 4: replace only queued tile data at consumption with data selected by the
  **live** scroll values, preserving the recorded register-update timing.
- Mode 3: replace queued data with the correct scanline-selected tiles, matching
  the reference HUD split. No RTL file is changed in either intervention.

| Title | Original vs scanline reference | Original vs live-scroll queue replacement | Live-scroll vs scanline reference |
|---|---|---|---|
| Pig Out | 15 pixels, Y=217, X=1..37 | Same 15 pixels | No differences |
| Brute Force | 87 pixels, Y=208, X=1..87 | Same 87 pixels | 31 pixels, Y=208, X=1..31 |

**Every other pixel in each 320x240 frame is identical.** Foreground RAM and
palette remain constant across the modes. The effect exists directly on the video
module's RGB output before the CRT retimer and HDMI scaler.

Changing the write times by just ±16 native pixels moves the last affected pixel:

| Timing offset | Pig Out last affected X | Brute Force last affected X |
|---|---:|---:|
| -16 pixels | 23 | 71 |
| Recorded timing | 37 | 87 |
| +16 pixels | 63 | 103 |

This explains why the line shifts during gameplay: instruction/interrupt timing
changes where the scroll write lands, while camera motion changes the contents of
the stale world tiles. The 80186 can affect timing and simulation cost; it is not
required to reproduce this video failure once the state and writes are replayed.

## Local artifacts and reproduction

- `hud_runs/hud_comparison.png`: enlarged HUD strips, original vs reference.
- `hud_runs/replay_metrics.json`: measured timing sweep and queue-only comparison.
- `hud_runs/{pigout,brutforc}/mame_hud_trace.log`: recorded gameplay I/O writes.
- `hud_runs/{pigout_sound,brutforc_sound}/hud_trace.log`: partial full-board traces.
- `hud_replay_tb.sv`: fast replay and simulation-only counterfactuals.
- `run_hud_replay.sh`, `prepare_hud_replay.py`, `analyze_hud_replay.py`: reproducible
  replay and analysis (WSL archlinux, Verilator 5.052, Python, Pillow, NumPy).
- `hud_mame.lua`: capture script for the installed Windows MAME.
- `setup_hud_diag.py`, `hud_diag_tb.sv`, `flist_hud_diag*.txt`: full-board
  instrumentation generated from the existing loader bench.

All raw ROMs, captures, run directories, and build outputs stay locally ignored.
Only diagnostic sources, this report, and ignore rules are new/changed.

The existing captured inputs are sufficient to rerun:

```sh
wsl -d archlinux -- bash <repo>/sim/run_hud_replay.sh
```

To recapture, first use `mra_to_image.py` with the worktree MRAs and the local
`C:/MiSTerDev/mame/roms` directory. Run `mame.exe <title>` from each corresponding
`sim/hud_runs/<title>` directory with `-rompath C:/MiSTerDev/mame/roms -video none
-sound none -nothrottle -skip_gameinfo -autoboot_delay 0 -autoboot_script
../../hud_mame.lua -nvram_directory nvram -cfg_directory cfg -snapshot_directory .`.
The Lua script captures Brute Force's memory at frame 600 and Pig Out's at frame 850;
Pig Out requires character choice and initials entry before gameplay.

The replay models ROM reads with a deterministic short latency and does not
reproduce the complete SDRAM arbitration load. Exact hardware strip widths can
therefore differ. Queue provenance, affected scanline, and pixel-level causality
are established; original PCB behavior is not.

## Fix

`leland_video.sv` now empties the tile queue and drops the fetch in flight whenever
`scroll_x` or `scroll_y` changes, so the producer refetches from the live position with
the new scroll. Flushing only the entries fetched for later rows was tried first: it fixes
Pig Out but not Brute Force, whose X-scroll write lands inside the first visible pixels of
the HUD row, where the entries are for the row already on screen.

Pixels differing from the scanline reference in the replay, original RTL vs the fix (the
`+LATENCY` plusarg of `hud_replay_tb.sv` sets the modelled ROM read latency in clocks):

| Title | Timing offset | Original | Fixed (latency 12 to 36) |
|---|---|---|---|
| Pig Out (line 217) | -16 / 0 / +16 pixels | 12 / 15 / 30 | 0 / 0 / 0 |
| Brute Force (line 208) | -16 / 0 / +16 pixels | 71 / 87 / 103 | 15 / 31 / 47 |

What remains for Brute Force is the part that cannot be recovered after the fact: pixels
already drawn before the first scroll write of the row. Whole-board runs of Super Off-Road,
Track-Pak, Pig Out, Ataxx and Indy Heat give frames identical to the build without the
change. Latencies above about 40 clocks starve the queue in the replay even for the
original RTL, so they say nothing about the fix.
