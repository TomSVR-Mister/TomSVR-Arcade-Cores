#!/bin/bash
cd "$(dirname "$0")"
verilator --binary --timing -Wno-fatal -j 8 --top-module leland_sound_ax2_tb -I../rtl/KF8253 -I../rtl/s80x86 -I../rtl/s80x86/microcode -Mdir verilator/obj_sax2 -f flist_sound_ax2.txt > verilator/build_sax2.log 2>&1
tail -5 verilator/build_sax2.log
ls verilator/obj_sax2 | grep -c Vleland
