#!/bin/bash
# builds the video bench; ROM images go in $XROMS (tiles.bin, lvc.bin, obj.bin)
S=/tmp/claude-0/-home-claude/183009bc-02e0-578a-b0ba-00b6083aaf64/scratchpad
J=$S/jtcores/modules/jtframe/hdl
SIM=$S/jtcores/cores/simson/hdl
H=$S/tomrepo/xexex/hdl
cd $(dirname $0)
verilator --cc --exe --build -O2 -Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE --top-module xvbench \
  -DXVDEBUG $VFLAGS -o xvbench xvbench.v xvbench.cpp \
  $H/jtxexex_video.v $H/jtxexex_tmap.v $H/jtxexex_lvc.v $H/jtxexex_colmix.v $H/jtxexex_obj.v \
  $H/jtxexex_k246.sv $H/jtxexex_k246_scan.sv $SIM/jt053246_dma.v $SIM/jt053246_mmr.v \
  $J/ram/jtframe_dual_ram.v $J/ram/jtframe_dual_ram16.v $J/video/jtframe_objdraw.v $J/video/jtframe_objdraw_gate.v \
  $J/video/jtframe_draw.v $J/ram/jtframe_obj_buffer.v $J/video/layouts/jtframe_8x8x4_packed_msb.v \
  -I$J/inc 2>&1 | grep -E "%Error|error" | head -30
