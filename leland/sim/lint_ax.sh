#!/bin/bash
cd "$(dirname "$0")"
verilator --lint-only -Wno-fatal --timing --top-module leland_board_ax_tb -I../rtl/KF8253 -I../rtl/s80x86 -I../rtl/s80x86/microcode -f flist_ax_snd_verilator.txt 2>&1 | grep -E "%Error|ERROR" | head -20
echo lint-done
