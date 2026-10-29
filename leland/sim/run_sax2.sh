#!/bin/bash
cd "$(dirname "$0")"
./verilator/obj_sax2/Vleland_sound_ax2_tb +MAX_CYCLES=${1:-560000000} +MAX_FRAME=${2:-700} > ${3:-ih_run2.log} 2>&1
