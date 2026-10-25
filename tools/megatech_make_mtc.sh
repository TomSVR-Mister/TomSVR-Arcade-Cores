#!/bin/bash
# Makes Mega-Tech cartridge files (.mtc) for the TomSVR_megatech core's slots 2-8 from your MAME zips.
# Reads the Mega-Tech MRAs in _Arcade and _Arcade/_TomSVR; writes /media/fat/games/Mega-Tech/<game>.mtc
for d in /media/fat/_Arcade /media/fat/_Arcade/_TomSVR; do
  [ -d "$d" ] && python3 /media/fat/Scripts/megatech_mtc.py "$d" /media/fat/games/mame /media/fat/games/Mega-Tech
done
