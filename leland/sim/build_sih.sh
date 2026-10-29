#!/bin/bash
cd "$(dirname "$0")"
verilator --binary --timing -Wno-fatal -j 8 --top-module leland_sound_ih_tb -I../rtl/KF8253 -I../rtl/s80x86 -I../rtl/s80x86/microcode -Mdir verilator/obj_sih -f flist_sound_ih.txt > verilator/build_sih.log 2>&1
tail -5 verilator/build_sih.log
ls verilator/obj_sih | grep -c Vleland
