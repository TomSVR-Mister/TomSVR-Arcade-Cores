#!/bin/bash
# Makes Mega-Tech cartridge files (.mtc) for the TomSVR_megatech core's slots 2-8 from your MAME zips.
# Reads the Mega-Tech MRAs in _Arcade (and its subfolders); writes /media/fat/games/Mega-Tech/<game>.mtc
python3 /media/fat/Scripts/megatech_mtc.py /media/fat/_Arcade /media/fat/games/mame /media/fat/games/Mega-Tech
