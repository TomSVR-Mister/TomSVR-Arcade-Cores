#!/bin/bash
cd "$(dirname "$0")"
ln -sfn ../../roms_src regress_phase_old/roms_src
for ph in 0 3700000 7600000 11400000; do
  d=regress_phase_old/pigout_$ph; rm -rf $d; mkdir -p $d; cp *.u* eeprom-offroad.bin bdab_wram_*.bin $d/ 2>/dev/null
  (cd $d && ../../verilator/obj_old_pigout/Vleland_board_tb +PHASE_NS=$ph > run.log 2>&1; echo "pigout $ph done") &
done
wait
