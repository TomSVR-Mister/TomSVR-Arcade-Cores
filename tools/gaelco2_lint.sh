#!/bin/bash
export JTROOT=/home/claude/jtcores JTFRAME=/home/claude/jtcores/modules/jtframe; source $JTFRAME/bin/setprj.sh >/dev/null 2>&1; export PATH=$JTFRAME/src/jtframe:$PATH
# verilator lint of the generated game_sdram top (mister macros)
jtframe cfgstr gaelco2 --target=mister --output=verilator | grep -v JTFRAME_SKIP > lint.def
(cd ../.. && jtframe mem gaelco2 >/dev/null); cp ../../mist/jtgaelco2_game_sdram.v ../../mist/mem_ports.inc .; jtframe files sim gaelco2 > /dev/null
verilator --lint-only -Wno-fatal -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-PINCONNECTEMPTY \
  -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNDRIVEN -Wno-VARHIDDEN -Wno-GENUNNAMED -Wno-CASEINCOMPLETE \
  --top-module jtgaelco2_game_sdram -f lint.def -f game.f -I$JTFRAME/hdl/inc -I../../mist -Wno-EOFNEWLINE -Wno-BLKANDNBLK -Wno-BLKSEQ -Wno-SYNCASYNCNET -I$JTFRAME/hdl/sdram \
  "$@" 2>&1 | grep -v "^\s*:" | grep -E "%(Error|Warning)" | grep -E "Error|gaelco2|aligator" | head -40
