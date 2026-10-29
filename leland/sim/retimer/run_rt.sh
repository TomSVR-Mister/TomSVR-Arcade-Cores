#!/bin/bash
cd "$(dirname "$0")"
mkdir -p ../verilator/rt
verilator --binary --timing -Wno-fatal --top-module tb_retimer2 ../../rtl/video/leland_retimer.sv tb_retimer2.sv --Mdir ../verilator/rt -j 8 > ../verilator/rt_build.log 2>&1 || { tail -20 ../verilator/rt_build.log; exit 1; }
B=../verilator/rt/Vtb_retimer2
for ax in 0 1; do
  echo "== ax=$ax coherence vsize0"; $B +vsize=0 +ax=$ax +mode=0 +ms=80 | grep -v "^- "
  echo "== ax=$ax const vsize3"; $B +vsize=3 +ax=$ax +mode=1 +ms=80 | grep -v "^- "
done
