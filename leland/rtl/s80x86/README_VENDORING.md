# s80x86 vendoring notes (WP1)

Vendored from `https://github.com/jamieiles/80x86`, commit
`a12778b40ae905f82eb2c23ea4ac037f98099fae` (2024-03-22), for
`docs/planning_80186_sound.md` WP1. **License: GPLv3** (`COPYING` in this
directory) — see `docs/planning_80186_sound.md` §3 / Q8 for why a GPLv3
component is acceptable in this repo.

**Do not hand-edit the generated files** (`microcode/Microcode.sv`,
`microcode/MicrocodeTypes.{sv,h}`, `microcode/microcode.{bin,mif}`,
`InstructionDefinitions.sv`) unless you're also updating the `.templ`/
`.us`/`documentation` source they derive from and regenerating. They're
vendored as generated output (not built by this repo's own toolchain)
because upstream's code generators (`scripts/microassembler/uasm`,
`scripts/gen-instructions-functions`) need Python packages and a real C
preprocessor that aren't part of this repo's normal build.

## What's vendored vs. not

- All of `rtl/*.sv`, `rtl/alu/`, `rtl/cdc/` — copied verbatim, unmodified.
- `rtl/microcode/*.us`, `*.templ`, `microcode_grammar.g` — copied
  verbatim (source of truth for the generated microcode ROM).
- `rtl/microcode/Microcode.sv`, `MicrocodeTypes.{sv,h}`,
  `microcode.{bin,mif}` — **generated**, committed as build output (see
  regeneration recipe below).
- `rtl/InstructionDefinitions.sv.templ` — copied verbatim.
- `rtl/InstructionDefinitions.sv` — **generated**, committed as build
  output.
- **Not vendored**: `fpga/`, `sim/` (their `RTLCPU.sv` reference harness
  is useful reading but not needed — this repo's Stage-A bench is
  standalone), `docker/`, `python/`, `tests/`, `CMakeLists.txt` (this
  repo's own `sim/` ModelSim flow supersedes it), `scripts/` (the
  generators — not needed again unless the microcode or instruction
  tables change; see recipe below to get them back), `documentation/`
  (needed only to regenerate `InstructionDefinitions.sv`).

## Config chosen for the generated files

`rtl/microcode/esc.us` includes a build-generated `config.h`
(from upstream's `config.h.in`, a CMake `#cmakedefine01` template) with
two flags. Both were set to **0** for this vendoring (plain 8086/80186
behavior, no 80287/80287-trap, no 80286 pseudo-protected-mode):

```c
#define S80X86_TRAP_ESCAPE 0   // ESC opcodes (0xD8-0xDF) execute as NOPs,
                                // not trapped -- Leland has no 8087/80287
#define S80X86_PSEUDO_286 0     // plain 8086/80186 mode
```

This matches Leland hardware (no coprocessor) and is consistent with
`docs/planning_80186_sound.md` §1.4's note that ESC-trap behavior is
irrelevant to this board.

## Regeneration recipe (if `.us`/`.yaml`/`.templ` sources ever change, e.g. WP9's WAIT/`test_n` patch)

This was non-trivial to get working on Windows with no system `gcc`/`cpp`
and a too-new default `textX`/`setuptools`. Steps, from a fresh clone of
`jamieiles/80x86`:

1. **Pin dependencies exactly** (newer versions break the 2017-era tool):
   ```
   pip install pystache "textX==1.6.1" "setuptools==75.6.0" pyyaml
   ```
   (`setuptools==75.6.0` restores `pkg_resources`, which `textX==1.6.1`
   needs and which modern `setuptools` dropped; `textX==1.6.1` matches
   the version pinned in upstream's own `docker/build/Dockerfile`.)
2. **No real `cpp` on Windows**: `uasm` shells out to a literal `cpp`
   executable found via Windows `CreateProcess` (bare name -- Windows
   does *not* try `PATHEXT` extensions here the way `cmd.exe` would).
   Options: install a real MinGW/MSYS2 gcc and put its `cpp.exe` on
   `PATH`, *or* use a pure-Python stand-in (`pip install pcpp`) behind a
   `cpp.bat` + shim script on `PATH`. The shim must:
   - drop `-nostdinc` (no-op for pcpp) and the `-o -` pair (default to
     stdout);
   - pass `--line-directive '#'` (pcpp defaults to `#line N`, but the
     tool's grammar expects GCC's classic `# N "file"` form with no
     `line` keyword);
   - **catch `SystemExit`** around `pcpp.main()` — it always calls
     `sys.exit()`, which if uncaught skips any output-capture logic
     wrapped around it;
   - **guarantee a leading `# 1 "file"` marker even for effectively-empty
     output** — real `cpp` always emits this, but `pcpp` emits *zero
     bytes* for a file whose entire body is preprocessor directives
     (e.g. `arithmetic.us`, a header-guarded macro-only file also listed
     directly as a top-level microassembler input). Without it, the
     grammar's `Microcode: lines*=Line;` collapses to a bare Python
     `str` instead of a model object and `uasm` crashes on
     `model.lines`.
3. **Generate a concrete `config.h`** from `config.h.in` (see above) and
   add its directory to `-I`.
4. Run the microassembler:
   ```
   uasm -I<repo-root> -I<dir-with-config.h> \
        microcode.bin microcode.mif Microcode.sv MicrocodeTypes.sv MicrocodeTypes.h \
        rtl/microcode/*.us
   ```
5. Run the instruction-table generator (no `cpp` needed, pure
   pystache+yaml):
   ```
   scripts/gen-instructions-functions InstructionDefinitions.sv
   ```
6. Copy the five generated files over the ones in this directory, diff
   against the previous version to sanity-check the change is what you
   expect, and re-run Stage A.

If a real `gcc`/`cpp` becomes available in this environment later, skip
the `cpp.bat` shim entirely — `uasm` just needs `cpp` to resolve.

## ModelSim ASE compatibility patch (on top of the verbatim vendor)

Upstream only ever validates this core through **Verilator** (see
`rtl/CMakeLists.txt`'s `verilate(...)` calls; there's no ModelSim/Questa
anywhere in the upstream repo). This repo's ModelSim (Altera ASE 10.5b,
2016, `intelFPGA_lite/17.0/modelsim_ase`) needed two categories of fix to
compile it, applied directly to the vendored files (not just at the
vendoring boundary, since these are real tool-compatibility issues, not
generation artifacts). **Both are pure, semantics-preserving mechanical
transforms — no logic changes** — and are called out inline at each edit
site with a comment referencing this section.

1. **Strict declare-before-use wire ordering.** This ModelSim requires
   every wire's bare declaration to textually precede its first use
   within a module — legal-but-forward-referencing SystemVerilog (which
   Verilator handles fine via full dependency-order elaboration) is
   rejected. Fixed in `Core.sv` (the big one — every `wire W X = E;`
   split into a hoisted `wire W X;` + a same-position `assign X = E;`,
   grouped into one declarations block right after the existing
   `Instruction` struct declarations), `microcode/Microcode.sv`
   (`trap_flag_set`), `Divider.sv` (`P`, `dividend_mag`, `divisor_mag`,
   `in_signs_equal`), `Fifo.sv` (`data_width` etc. — moved from trailing
   `parameter` statements into a proper `#(...)` parameter port list,
   the equivalent modern ANSI form), `ImmediateReader.sv` (`_fetching`),
   `LoadStore.sv` (`unaligned`, `fetching`, `second_byte`), and
   `cdc/MCP.sv` (`a_ack`, `tx_busy`). Each site has an inline comment.
2. **`` `default_nettype none `` produces false `vlog-2892` "Net type
   must be explicitly declared" errors on fully-typed ANSI ports** when
   combined with `-mfcu` (needed — see below) on this ModelSim version.
   Confirmed by isolated test: removing the directive from one file made
   its false errors disappear with zero other changes; every port in
   every affected file already has an explicit `logic`/`wire`/`reg`
   type, so the directive was providing no actual safety net-inference
   check here anyway. Fixed by commenting it out (with an explanatory
   note) in all 22 `.sv` files that had it, plus `microcode/Microcode.sv.templ`
   so regeneration doesn't reintroduce it.
3. Two unrelated trivial fixes while at it: `alu/daa.sv` and
   `alu/das.sv` had a `reg [15:0] tmp = expr;` inside a function's
   nested `begin...end` block that this ModelSim flags as "implicitly
   static" without `-permissive` — added the `automatic` keyword
   (standard SV, no behavior change for a non-recursive function).

**Compile command** (from `sim/`, this repo's working ModelSim
directory): the exact dependency order matters (re-derived from
upstream's own `rtl/CMakeLists.txt` `CORE_SOURCES` list, with
`FlagsEnum.sv` moved earlier — upstream's own order has ALU files using
`FlagsEnum.sv` constants like `CF_IDX` *before* `FlagsEnum.sv` compiles,
which only works for Verilator's whole-design elaboration, not this
tool). `.f` filelists are gitignored repo-wide in this project, so the
list is reproduced here verbatim rather than committed as a file —
regenerate it locally (e.g. `sim/s80x86_core_filelist.f`) rather than
hunting for a missing committed copy:

```
vlog -sv -mfcu -work <your_work_lib> -f s80x86_core_filelist.f
```

where `s80x86_core_filelist.f` (paths relative to `sim/`) is:

```
../rtl/s80x86/config.v
../rtl/s80x86/microcode/MicrocodeTypes.sv
../rtl/s80x86/FlagsEnum.sv
../rtl/s80x86/alu/aaa.sv
../rtl/s80x86/alu/aas.sv
../rtl/s80x86/alu/adc.sv
../rtl/s80x86/alu/add.sv
../rtl/s80x86/alu/and.sv
../rtl/s80x86/alu/bound.sv
../rtl/s80x86/alu/daa.sv
../rtl/s80x86/alu/das.sv
../rtl/s80x86/alu/enter.sv
../rtl/s80x86/alu/extend.sv
../rtl/s80x86/alu/flags.sv
../rtl/s80x86/alu/mul.sv
../rtl/s80x86/alu/or.sv
../rtl/s80x86/alu/not.sv
../rtl/s80x86/alu/rcl.sv
../rtl/s80x86/alu/rcr.sv
../rtl/s80x86/alu/rol.sv
../rtl/s80x86/alu/ror.sv
../rtl/s80x86/alu/sar.sv
../rtl/s80x86/alu/shift_flags.sv
../rtl/s80x86/alu/shl.sv
../rtl/s80x86/alu/shr.sv
../rtl/s80x86/alu/sub.sv
../rtl/s80x86/alu/xor.sv
../rtl/s80x86/alu/ALU.sv
../rtl/s80x86/RegisterEnum.sv
../rtl/s80x86/Instruction.sv
../rtl/s80x86/InstructionDefinitions.sv
../rtl/s80x86/InsnDecoder.sv
../rtl/s80x86/microcode/Microcode.sv
../rtl/s80x86/Core.sv
../rtl/s80x86/CSIPSync.sv
../rtl/s80x86/Divider.sv
../rtl/s80x86/Fifo.sv
../rtl/s80x86/Flags.sv
../rtl/s80x86/ImmediateReader.sv
../rtl/s80x86/IP.sv
../rtl/s80x86/JumpTest.sv
../rtl/s80x86/LoadStore.sv
../rtl/s80x86/LoopCounter.sv
../rtl/s80x86/ModRMDecode.sv
../rtl/s80x86/PosedgeToPulse.sv
../rtl/s80x86/Prefetch.sv
../rtl/s80x86/RegisterFile.sv
../rtl/s80x86/SegmentOverride.sv
../rtl/s80x86/SegmentRegisterFile.sv
../rtl/s80x86/TempReg.sv
../rtl/s80x86/cdc/BitSync.sv
../rtl/s80x86/cdc/MCP.sv
../rtl/s80x86/cdc/SyncPulse.sv
../rtl/s80x86/MemArbiter.sv
```

`-mfcu` (merge files into one compilation unit) is required — this
ModelSim defaults to per-file compilation units, which hides the
package-less global enum/macro definitions (`ALUOp_t` members, `CF_IDX`
etc.) from every other file even though they're declared in the same
committed, ordered source tree. Zero errors, zero warnings as of this
writing; `-permissive` is **not** needed once the two `daa.sv`/`das.sv`
fixes above are in place.

If the microcode/instruction-table generation step (above) is ever
re-run and produces a fresh `Microcode.sv`, the declare-before-use fix
for `trap_flag_set` will need to be reapplied to the new file (the
`.templ` already has the `default_nettype` fix baked in, but the
declaration-order fix lives in generated, not templated, code — check
`docs/WP1_PROGRESS.md` for whether the templ itself has since been
patched too).
