# Leland sports pack (TomSVR)

A fork of the official MiSTer Leland core by shimian5
([MiSTer-devel/Arcade-Leland_MiSTer](https://github.com/MiSTer-devel/Arcade-Leland_MiSTer), commit `2dc128a`,
GPL-3.0-or-later). The official core runs Ataxx, Super Off-Road, Pig Out, Indy Heat and Brute Force. This fork adds five
more Leland games from MAME 0.264 (`leland.cpp`) on the same boards:

| Game | MAME sets | Board | Controls |
|------|-----------|-------|----------|
| Viper (1988) | viper | lelandi | trackball (mouse, analog stick or D-pad), Fire, Bomb |
| John Elway's Team Quarterback (1988) | teamqb, teamqb2 | lelandi | 4 players, spring analog sticks (analog stick or D-pad), Pass |
| All American Football (1989) | aafb, aafbc, aafbd2p (2 players) | lelandi | as Team Quarterback |
| Quarterback (1987) | quarterb, quarterba, quarterbc | lelandi (small slave memory map) | 2 players, as Team Quarterback |
| World Soccer Finals (1990) | wsf, wsf3 | WSF (Indy Heat board) | 4 players, joystick, Kick, Pass |

Changes from the official core:

- Game table entries, input schemes and MAME's per-game I/O and video RAM bases (`rtl/leland_board_pkg.sv`).
- Viper's master bank switching, Danger Zone style trackball ports, the Team QB / AAFB analog stick multiplexer
  and extra input ports (`rtl/cpu/leland_master.sv`), World Soccer Finals inputs (`rtl/cpu/leland_master_ataxx.sv`),
  Quarterback's small slave memory map (`rtl/cpu/leland_slave.sv`).
- Vertical games (Team QB, AAFB, Quarterback) are turned upright on HDMI through the frame buffer (`screen_rotate`).
  OSD Video Settings: "Vertical Games" (Rotate / Original) and "Rotate Direction". The CRT retimer is off while rotating.
- `sys/pll_q20.qip` so the project builds with Quartus 20.1.
- The tv80 and jt51 submodules are included as plain files.

Coin is on the pad's Select button and Start on Start, with no mapping needed. The MRAs come from
`tools/leland_build.py` (run it on MAME 0.264's `src/mame/leland/leland.cpp`) and use MAME's zips unchanged.
Build: open `Leland.qpf` in Quartus. Bench: `sim/sports_board_tb.sv` with `sim/flist_sports_*.txt`.
