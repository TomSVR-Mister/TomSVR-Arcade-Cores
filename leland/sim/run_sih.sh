#!/bin/bash
cd "$(dirname "$0")"
./verilator/obj_sih/Vleland_sound_ih_tb +MAX_CYCLES=${1:-560000000} +MAX_FRAME=${2:-700} > ${3:-ih_run2.log} 2>&1
