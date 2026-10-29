#!/bin/bash
cd "$(dirname "$0")"
mkdir -p verilator regress
verilator --binary --timing -Wno-fatal -DSIM_NO_SOUND -DRUN_LEN_MS=3300 --top-module leland_board_ax_tb -I../rtl/KF8253 -I../rtl/s80x86 -I../rtl/s80x86/microcode -f flist_ax_verilator.txt --Mdir verilator/obj_axr -j 8 > verilator/build_axr.log 2>&1
cd regress && ln -sf ../ataxx_image.bin . && ../verilator/obj_axr/Vleland_board_ax_tb > run.log 2>&1
tail -2 run.log
ls
