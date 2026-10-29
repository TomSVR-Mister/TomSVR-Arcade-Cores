#!/bin/bash
cd "$(dirname "$0")"
verilator --binary --timing -Wno-fatal -j 8 --top-module jt51_seq_tb -Mdir verilator/obj_seq -f flist_jt51_seq.txt > verilator/build_seq.log 2>&1
./verilator/obj_seq/Vjt51_seq_tb 2>&1 | tail -3
