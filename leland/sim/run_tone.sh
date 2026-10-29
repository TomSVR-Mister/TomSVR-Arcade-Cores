#!/bin/bash
cd "$(dirname "$0")"
verilator --binary --timing -Wno-fatal -j 8 --top-module jt51_tone_tb -Mdir verilator/obj_tone -f flist_jt51_tone.txt > verilator/build_tone.log 2>&1
./verilator/obj_tone/Vjt51_tone_tb 2>&1 | tail -3
