#!/bin/bash
# Boot every game from several raster phases and keep the frame dumps for inspection.
#   ./run_phase.sh [run_len_ms] [parallel jobs]
cd "$(dirname "$0")"
LEN=${1:-4000}
JOBS=${2:-12}
mkdir -p verilator regress_phase
verilator --binary --timing -Wno-fatal -DSIM_NO_SOUND -DRUN_LEN_MS=$LEN --top-module leland_board_ax_tb -I../rtl/KF8253 -I../rtl/s80x86 -I../rtl/s80x86/microcode -f flist_ax_verilator.txt --Mdir verilator/obj_ph -j 16 > verilator/build_ph.log 2>&1 || { tail -20 verilator/build_ph.log; exit 1; }
rm -rf regress_phase/*
for g in ataxx indyheat offroad offroadt pigout; do
  for ph in 0 3700000 7600000 11400000; do
    echo "$g $ph"
  done
done | xargs -P $JOBS -L 1 bash -c 'g=$0; ph=$1; d=regress_phase/${g}_${ph}; mkdir -p $d; (cd $d && ../../verilator/obj_ph/Vleland_board_ax_tb +IMG=../../images/$g.bin +PHASE_NS=$ph > run.log 2>&1; echo "$g $ph done")'
