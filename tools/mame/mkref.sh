#!/bin/bash
# mkref.sh set [frames]  -> ref_<set>/NNNN.png, NNNN = k for MAME frame 2(k+1)
S=/tmp/claude-0/-home-claude/e1042311-2b93-5281-bddb-91ed22183aec/scratchpad
cd $S/mame; N=${2:-2000}
./obs.sh $1 $N ${HOOK:-hook_any.lua} "$(seq -s, 2 2 $N)"
rm -rf ref_$1; mkdir ref_$1; i=0
for f in $(ls snapobs_$1/$1/ | sort -n); do mv snapobs_$1/$1/$f ref_$1/$(printf %04d $i).png; i=$((i+1)); done
echo "$1: $i frames"
