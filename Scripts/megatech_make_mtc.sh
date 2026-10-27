#!/bin/bash
# Makes Mega-Tech (.mtc, slots 2-8) and Mega Play (.mpc, slots 2-4) cartridge files from your MAME zips.
# Reads the TomSVR Mega-Tech/Mega Play MRAs in _Arcade (and subfolders); writes games/Mega-Tech/*.mtc and games/Mega Play/*.mpc
python3 /media/fat/Scripts/megatech_mtc.py /media/fat/_Arcade /media/fat/games/mame /media/fat/games/Mega-Tech
