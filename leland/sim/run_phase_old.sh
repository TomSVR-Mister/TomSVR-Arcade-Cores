#!/bin/bash
# Off-Road and Pig Out from several raster phases through the full board bench.
cd "$(dirname "$0")"
LEN=${1:-1600}
mkdir -p verilator regress_phase_old
for g in ${GAMES:-offroad pigout}; do
  DEF="-DSIM_NO_SOUND -DSCANOUT_DUMP -DRUN_LEN_MS=$LEN"
  [ $g = pigout ] && DEF="$DEF -DPIGOUT_ROMS"
  verilator --binary --timing -Wno-fatal $DEF --top-module leland_board_tb -I../rtl/KF8253 -I../rtl/s80x86 -I../rtl/s80x86/microcode -f flist_board_verilator.txt --Mdir verilator/obj_old_$g -j 8 > verilator/build_old_$g.log 2>&1 || { tail -20 verilator/build_old_$g.log; exit 1; }
done
rm -rf regress_phase_old/*
for g in ${GAMES:-offroad pigout}; do
  for ph in 0 3700000 7600000 11400000; do echo "$g $ph"; done
done | xargs -P 8 -L 1 bash -c 'g=$0; ph=$1; d=regress_phase_old/${g}_${ph}; mkdir -p $d; cp *.u* eeprom-offroad.bin bdab_wram_*.bin $d/ 2>/dev/null; (cd $d && ../../verilator/obj_old_$g/Vleland_board_tb +PHASE_NS=$ph > run.log 2>&1; echo "$g $ph done")'
