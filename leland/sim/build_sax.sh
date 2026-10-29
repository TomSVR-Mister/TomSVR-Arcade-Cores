#!/bin/bash
cd "$(dirname "$0")"
verilator --binary --timing -Wno-fatal -j 8 --top-module leland_sound_ax_tb -I../rtl/KF8253 -I../rtl/s80x86 -I../rtl/s80x86/microcode -Mdir verilator/obj_sax -f flist_sound_ax.txt > verilator/build_sax.log 2>&1
tail -5 verilator/build_sax.log
ls verilator/obj_sax | grep -c Vleland
