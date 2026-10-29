# Brute Force residual HUD pixels: hardware timing investigation

2026-10-02. Baseline `ef2bc86`, with the tile-queue flush of `0e4ca16` applied.

## Finding

The remaining strip is reproduced by the real ROM's interrupt-handler timing,
even after the existing FIFO-flush fix. The master Z80 does not appear to have a
large interrupt-to-scroll delay relative to MAME. The strongest remaining
accuracy question is the horizontal phase of the raster interrupt relative to
visible video, followed by the original board's horizontal-scroll counter reload
timing.

**The 31-pixel result is a floor of the current live-scroll/tile-boundary replay,
not proof of an unavoidable defect on an original Brute Force PCB.** MAME's
whole-scanline update is also not a hardware measurement.

No synthesizable RTL was changed in this investigation. The video module already
contained the FIFO-flush change when the experiments started.

## Isolated real-ROM ISR experiment

`hud_irq_timing_tb.sv` runs the existing TV80 CPU wrapper at 6 MHz, with its actual
`Mode=0`, `T2Write=1`, `IOWait=1` settings. It reads the captured Brute Force fixed
ROM, retains the interrupt vector and handler, initializes RAM location E012 to
CE, and substitutes only a short DI/SP/IM1/EI/HALT reset bootstrap. Port F7 reads
FF to select the active-picture handler. Memory responds without ROM stalls.
The 80186, game boot, video memory arbiter and the main game's interrupt masking
are deliberately absent: this establishes the handler's minimum timing.

The ROM contains a 13-iteration `DEC A / JR NZ` delay at 00FA before the four
scroll writes. Interrupt assertion is swept across all 32 system-clock positions
of a four-T-state HALT cycle. The bench records the first CPU-enable edge on which
the I/O write strobe is active, corresponding to the board's register sampling.

| Write | Purpose | T states after IRQ, min..max | Native pixels after IRQ, min..max |
|---|---|---:|---:|
| F3=03 | Y high byte | 330..333.875 | 393.750..398.374 |
| F2=10 | Y low byte | 348..351.875 | 415.227..419.851 |
| F0=00 | X low byte | 363..366.875 | 433.125..437.749 |
| F1=00 | X high byte | 374..377.875 | 446.250..450.874 |
| F8=EF | Schedule next IRQ | 428..431.875 | 510.682..515.305 |

A scanline is 424 pixels. With the IRQ at visible line 207, X=0, the final X
write therefore lands on line 208, X=22.25..26.87. The captured MAME frame lands
at X=24. Its earlier writes are likewise inside the measured TV80 ranges.

Consequently, changing CPU speed or removing CPU wait states is not supported as
a correction for the nominal 31-pixel residual. Actual instruction completion,
masked interrupts or memory contention can still move writes later. This bench
does not establish a worst-case bound for the complete game.

## Whole-frame phase experiment

The existing real-ROM video replay was rebuilt against the current FIFO-flush
RTL. Every recorded HUD scroll write is shifted by the same phase, representing
an earlier interrupt with otherwise unchanged handler execution. This is a
counterfactual, not a physical-board calibration. The world-scroll restore in
vertical blank remains unchanged.

Each phase is tested at deterministic ROM-response countdowns of 12, 24, 36 and
48 system clocks. These are **testbench settings**, not measured SDRAM round-trip
times. The handshake and fetch state machine add further cycles. Three modes are
run: actual FIFO fix, ideal live-scroll tile supply at FIFO consumption, and ideal
scanline-selected tile supply at consumption. Comparisons below use one fixed
canonical image: the scanline-selected run at phase 0/countdown 12.

| Write advance, native pixels | Actual mismatch count at countdown 12 / 24 / 36 / 48 | Location |
|---:|---:|---|
| 0 | 31 / 31 / 31 / 39 | First HUD row, Y=208 |
| 16 | 15 / 15 / 15 / 23 | First HUD row |
| 24 | 7 / 7 / 7 / 15 | First HUD row |
| 32 | 0 / 0 / 0 / 7 | First HUD row if present |
| 40 | 0 / 0 / 0 / 0 | No differing pixels anywhere in frame |
| 48 | 0 / 0 / 0 / 0 | No differing pixels anywhere in frame |
| 64 | 0 / 0 / 0 / 0 | No differing pixels anywhere in frame |
| 80 | 0 / 0 / 0 / 0 | No differing pixels anywhere in frame |
| 104 | 21 / 19 / 19 / 14 | **Preceding world row, Y=207** |

Thus a 40..80-pixel advance, or 5.59..11.17 microseconds, is a clean sampled
window in this snapshot. A full horizontal-blanking advance of 104 pixels is
too early: it changes visible world pixels before the HUD. These results do not
justify a hard-coded title-specific offset or extrapolation to all game states.

For scale, an IRQ at the end of the core's existing HSync interval (preceding
line X=384) would be 40 pixels earlier than its present assertion at X=0.
That is an interesting candidate because it falls in the clean window, **not
evidence that the physical board asserts there**.

The ideal-live intervention agrees with actual Brute Force output throughout
the clean window. At the recorded phase, its result retains 31 pixels because
the final X byte arrives after drawing begins and displayed tile data is updated
on eight-pixel boundaries. Faster queued-tile replacement alone cannot undo that
timing. Nor does this intervention model the physical board's counter behavior.

### Pig Out control and latency limits

All tested phases remain frame-identical to the canonical Pig Out image at
countdown 12. At countdown 24, some phases produce one residual pixel at Y=217,
X=9; ideal tile replacement eliminates it. At countdown 36 and 48, unrelated
mid-picture errors occur even in runs that share the same scroll-write phase.
For example, countdown 36 produces 95 differing pixels on rows 120/121 before
the HUD write, plus one HUD pixel. These longer-latency Pig Out runs cannot be
treated as evidence of a general clean-hardware regression. The prior "Pig Out
is completely fixed" statement is supported by the nominal replay, not by all
possible memory latency or contention.

## What the primary hardware sources establish

The local Super Off Road manual contains older Cinemat-system logic schematics:

- PDF page 51, sheet 13: CPU X-scroll latches feed the parallel inputs of a
  74LS461 counter, with `/SRL` on its clock and `BHCNT` on its function input.
  The low three X bits also feed video timing logic.
- PDF page 52, sheet 14: Y-scroll latches feed 74LS283 adders together with raster
  address bits. X and Y therefore do not have identical physical mechanisms.
- PDF page 46, sheet 8: raster and background timing depend on RGS-07/RGS-08
  programmable logic. Wiring alone does not establish their exact output phase.

The original National Semiconductor 74LS461 datasheet confirms that counter
loading/counting happens at a rising clock edge, selected by the function inputs.
This is a reason to investigate horizontal reload semantics rather than assume
that every CPU X write instantly changes `hc + scroll_x` throughout a scanline.
It does **not** justify a frame-wide scroll latch.

The drawings are dated 1985 and describe an older board, not Brute Force's
Ataxx/WSF generation. The locally available Indy Heat owner's manual provides
wiring/layout information but no equivalent video timing circuit. MAME lists
the older RGS-07/08 timing PALs as undumped. No verified Brute Force timing PAL
equations or direct PCB IRQ/video phase measurement was found.

Primary sources:

- [Leland Super Off Road manual](https://www.arcade-museum.com/manuals-videogames/S/SuperOffRoad.pdf).
- [National Semiconductor DM74LS461 datasheet](https://k1.spdns.de/Develop/Hardware/Infomix/ICs%20logic/74xxx/74461.LS.pdf).
- [MAME Leland driver](https://github.com/mamedev/mame/blob/master/src/mame/cinematronics/leland.cpp)
  and its adjacent `leland_m.cpp` / `leland_v.cpp`: useful implementation
  references, but their scanline scheduling is not a measured hardware waveform.

## Interpretation for improving accuracy beyond MAME

Confirmed: stale queued tiles caused the larger original line; after flushing,
the remaining nominal strip follows real software write timing under the current
IRQ/video phase. A large TV80 timing error is not needed to reproduce it.

Unconfirmed: whether the original Brute Force board exposes that strip at all,
whether its raster IRQ is earlier in horizontal blanking, and exactly when its
coarse X counter reloads. The user has no original PCB available for measurement.

A hardware-faithful correction should model the board's raster phase and scroll
reload behavior, if reliable board-specific evidence becomes available. Changing
the interrupt to X=384 merely because it makes this image clean would be a
speculative compatibility change. Delaying presentation of a line and applying
later writes retroactively would reproduce MAME's line-level behavior but would
not establish higher physical accuracy either.

## Reproduce and review

With the existing ignored captures and fixed ROM extraction present:

```sh
wsl -d archlinux -- bash <repo>/sim/run_hud_timing.sh
```

This runs 32 isolated ISR cases and 216 video replays. The analyzer verifies the
five exact I/O writes in every ISR case, all clean-window Brute Force results,
the preceding-row failure at advance 104, and nominal Pig Out frame equivalence.

Ignored outputs in `sim/hud_runs/timing/`:

- `irq_phase_sweep.log`, `irq_wave_run.log`, `hud_irq_timing.vcd`.
- `phase_metrics.json`, `phase_summary.txt`.
- `brutforc_phase_comparison.png`: visible HUD strips including the preceding row.
- Primary-source inspection renders and the downloaded counter datasheet.

The picture comparator is a timing-sensitivity test with frozen RAM/palette and
deterministic ROM responses. It is not a complete-board or real-SDRAM regression,
nor an independent verification of every output pixel against an original PCB.
