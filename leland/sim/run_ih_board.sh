#!/bin/bash
cd "$(dirname "$0")"
mkdir -p verilator regress_ih
verilator --binary --timing -Wno-fatal -DSIM_NO_SOUND -DRUN_LEN_MS=6700 --top-module leland_board_ax_tb -I../rtl/KF8253 -I../rtl/s80x86 -I../rtl/s80x86/microcode -f flist_ax_verilator.txt --Mdir verilator/obj_ihr -j 8 > verilator/build_ihr.log 2>&1
cd regress_ih && ../verilator/obj_ihr/Vleland_board_ax_tb > run.log 2>&1
tail -2 run.log
ls
