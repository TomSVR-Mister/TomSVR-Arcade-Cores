#!/bin/bash
# obs.sh game frames hook [snapframes]
S=/tmp/claude-0/-home-claude/e1042311-2b93-5281-bddb-91ed22183aec/scratchpad
cd $S/mame; export PATH=$PATH:/usr/games SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
rm -rf snapobs_$1; mkdir -p cfgobs_$1; [ -n "$CFGKEEP" ] || true
SNAPF="${4:-$2}" HOOK=$3 timeout ${TMO:-1500} mame $1 -rompath roms -snapshot_directory snapobs_$1 -cfg_directory cfgobs_$1 -nvram_directory cfgobs_$1 -video none -sound none -skip_gameinfo -nothrottle -autoboot_script refplay.lua -snapname "%g/%i" 2>&1 | grep -v -e ALSA -e "doesn't make" -e WRONG -e EXPECTED -e FOUND -e "WARNING"
