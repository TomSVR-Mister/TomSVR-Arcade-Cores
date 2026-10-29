#!/bin/bash
# Run in WSL2 archlinux. Requires the captured mame_*.bin files and gfx/PROM images.
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")"
mkdir -p verilator
python prepare_hud_replay.py
verilator --binary --timing -Wno-fatal --top-module hud_replay_tb \
  ../rtl/leland_board_pkg.sv ../rtl/video/leland_video.sv hud_replay_tb.sv \
  --Mdir verilator/obj_hud_replay -j 12 > verilator/build_hud_replay.log 2>&1
for game_name in brutforc pigout; do
  (
    cd "hud_runs/$game_name"
    game=1; bank=0
    if [[ $game_name == pigout ]]; then game=0; bank=7; fi
    for phase in -16 0 16; do
      for mode in 0 3 4; do
        ../../verilator/obj_hud_replay/Vhud_replay_tb \
          +GAME="$game" +BANK="$bank" +MODE="$mode" +PHASE="$phase" \
          > "replay_${mode}_${phase}.log" 2>&1
      done
    done
  )
done
python analyze_hud_replay.py
