# Simulation

ModelSim (Intel FPGA Edition 10.5b) testbenches for the Leland core. Everything runs headless from
this directory and needs no Quartus simulation libraries. `sim/README.md` is the only
documentation here; each testbench's header comment says what it checks.

| Testbench | DUT |
|---|---|
| `sdram_tb.sv` | `rtl/mem/sdram.sv` against Micron's `mt48lc16m16a2` model |
| `sdram_burst_tb.sv`, `sdram_margin_tb.sv` | `rtl/mem/sdram_banked.sv` burst reads and timing margin |
| `leland_video_tb.sv` | `rtl/video/leland_video.sv` tile fetch and pixel output |
| `retimer/tb_retimer2.sv`, `retimer/tb_loader.sv` | CRT retimer and DDR fast loader |
| `leland_board_tb.sv` | whole board (both Z80s, video, SDRAM, sound), driven like the HPS loader |
| `leland_board_tb_svc.sv` | same, exercising the service-menu path |
| `leland_sound_tb.sv`, `leland_sound_board_tb.sv`, `leland_sound_smoketest_tb.sv` | 80186 sound board |
| `leland_dac_mixer_tb.sv` | DAC mixer gain math |
| `i186_*_tb.sv`, `s80x86_*_tb.sv`, `kf8253_leland_bus_tb.sv` | 80186 peripherals, CPU core and 8254 timer |

`mt48lc16m16a2.v` is Micron's behavioral SDRAM model (4M x 16 x 4 banks, the DE10-Nano's stock
32 MB part; `+define+MT48LC32M16` selects the 64 MB geometry). `mt48lc16m16a2_vl.v` is a
Verilator-clean fork of it. `timescale.v` and `test-defines.v` are stub includes the Micron
model expects.

## File lists

The board and sound benches use the `flist_*.txt` files. Each starts with the exact commands for
that run. All need `-mfcu -sv` and the include directories for the vendored cores:

```sh
vlib work
vlog -mfcu -sv -suppress 2244 \
  +incdir+../rtl/KF8253 +incdir+../rtl/s80x86 +incdir+../rtl/s80x86/microcode \
  -f flist_board_banked.txt
vsim -c work.leland_board_tb -do "run -all; quit"
```

| List | Use |
|---|---|
| `flist_board_banked.txt` | full board with the shipped banked SDRAM controller |
| `flist_board_nosnd.txt` | same without the sound board (`+define+SIM_NO_SOUND`), much faster |
| `flist_board_verilator.txt` | same with the Verilator-clean SDRAM model |
| `flist_sound_full.txt` | sound board on its own, `leland_sound_tb` |

`-suppress 2244` silences vlog's "implicit static" warning for two locals with inline
initializers in `sdram.sv`. Adding `static` to satisfy it breaks Quartus synthesis, so leave the
RTL alone.

## ROM files

The board and video benches read the MAME `offroad` ROM chip files (`03-22100-02.u3` and the
rest, same names the MRA uses) as raw binaries from `sim/`. They are copyrighted and gitignored,
so copy them in yourself. A missing file fails fast with `ERROR: could not open ...`.

## SDRAM controller test

```sh
vlib work
vlog -suppress 2244 +incdir+. mt48lc16m16a2.v ../rtl/mem/sdram.sv sdram_tb.sv
vsim -c work.sdram_tb -do "run -all; quit"
```

The last lines are `=== SUMMARY: <N> checks, <N> errors ===` and `=== PASS ===` or `=== FAIL ===`.
Each `FAIL [...]` line gives the check name, address, and expected versus actual byte.

Run it again with `+define+MT48LC32M16` on the vlog line to test the 64 MB geometry (10-bit
column). MiSTer boards can carry 32 MB, 64 MB or 128 MB SDRAM and the controller doesn't know
which; the row-boundary cases straddle both column widths to show it doesn't matter.

Reading a failure:

- `[isolated-byte]` fails on the simplest access, so look at the FSM and DQM logic.
- `[seq-fwd-rd0]` or `[seq-rev-rd2]` failing alone points at back-to-back requests:
  arbitration, the cache-hit word optimization, or refresh interrupting a transaction.
- `[bank-boundary]` or `[row-boundary-*]` points at the address decomposition.
- The Micron model prints its own timing-violation messages. Read them even when every check
  passes, because marginal timing that works in simulation can fail on silicon.
- The model's `Debug` flag (off by default) prints every ACT/READ/WRITE/AREF command. It is very
  verbose across a full run.

## Board testbench

`leland_board_tb.sv` instantiates `leland_board.sv` unmodified with both Z80s running, streams
the ROM image through the real `ioctl_*` path (toggling `ioctl_download` between parts like the
MRA does), then lets the master CPU boot. It prints `IOWR` lines for every I/O write (port, data,
PC, whether it hit the bank register or `/MCONT`) and a periodic `PC_SAMPLE` with the live PC and
bank register, which shows where boot code stalls. Loading the image takes noticeably longer than
`sdram_tb.sv`. The run ends with `=== PASS ===` or `=== FAIL ===`.
