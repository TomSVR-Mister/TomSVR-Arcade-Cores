# NEC V30 model

These files are the V30 CPU model of the MiSTer Irem M72 core by Martin Donlon (wickerwaka),
https://github.com/MiSTer-devel/Arcade-IremM72_MiSTer, commit 15c370e6e034a5e8baeea5a6fa651ff95b216c2b,
licensed under the GNU General Public License version 2 (LICENSE.GPL-2).

Changes for JTDYNDUKE:
- `v30u_eu.sv` has its `.svh` include files inlined, because Verilator does not search the folder of the including file.
- `v30u_ucrom.sv`: the `#0` delay in the simulation-only load check is removed (Verilator runs without --timing).
- `v30u_ucrom.sv` reads `ucrom.hex` and `ucdecode.hex` from the build folder (HEXDIR is empty); JTFRAME links them there from `hdl/`.

`jtdynduke_cpu.sv` and `jtdynduke_ssbus.sv` are new files for this core: the clock enable around the V30 bus adapter,
and a minimal stand-in for the M72 save-state bus interface, which this core does not use.
- Simulation-only blocks are guarded with `ifdef SIMULATION` (jtframe defines it in simulation) instead of `ifndef SYNTHESIS`, which Quartus does not define.
