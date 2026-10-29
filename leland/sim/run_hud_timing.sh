#!/bin/bash
# Hardware-phase experiments only; does not edit synthesizable RTL.
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")"
verilator --binary --timing --trace -Wno-fatal --top-module hud_irq_timing_tb \
 ../rtl/tv80/rtl/core/tv80_alu.v ../rtl/tv80/rtl/core/tv80_reg.v \
 ../rtl/tv80/rtl/core/tv80_mcode.v ../rtl/tv80/rtl/core/tv80_core.v \
 ../rtl/cpu/tv80s_ce.v hud_irq_timing_tb.sv \
 --Mdir verilator/obj_hud_irq_timing -j 12 > hud_runs/timing/build_irq.log 2>&1
(
 cd hud_runs/timing
 for phase in $(seq 0 31); do
  ../../verilator/obj_hud_irq_timing/Vhud_irq_timing_tb +IRQ_PHASE="$phase"
 done > irq_phase_sweep.log
)
verilator --binary --timing -Wno-fatal --top-module hud_replay_tb \
 ../rtl/leland_board_pkg.sv ../rtl/video/leland_video.sv hud_replay_tb.sv \
 --Mdir verilator/obj_hud_phase_replay -j 12 > hud_runs/timing/build_phase.log 2>&1
for title in brutforc pigout; do
 (
  cd "hud_runs/$title"
  game=1;bank=0
  if [[ $title == pigout ]]; then game=0;bank=7;fi
  for latency in 12 24 36 48; do
   for phase in 0 -16 -24 -32 -40 -48 -64 -80 -104; do
    for mode in 0 3 4; do
     ../../verilator/obj_hud_phase_replay/Vhud_replay_tb \
      +GAME="$game" +BANK="$bank" +MODE="$mode" +PHASE="$phase" +LATENCY="$latency" \
      > "phase_mode${mode}_phase${phase}_lat${latency}.log" 2>&1
    done
   done
  done
 )
done
python analyze_hud_timing.py > hud_runs/timing/phase_summary.txt
cat hud_runs/timing/phase_summary.txt
