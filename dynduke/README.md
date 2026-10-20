# JTDYNDUKE: personal MiSTer core for Seibu's Dynamite Duke

Built on JTFRAME by Jose Tejada (jotego), GPL-3.0-or-later. Not affiliated with or supported by jotego.
Hardware description from MAME dynduke.cpp.

Sets: Dynamite Duke (Europe 03SEP89 and 25JUL89, Japan 03SEP89 and 25JUL89, US 25JUL89).
The core also has The Double Dynamites' I/O map (header byte 0 bit 0), but no MRAs for it yet.

- Two NEC V30 CPUs at 8 MHz sharing 4 kB of RAM: the master runs the game, the slave draws the scroll layers
  and the palette
- Seibu sound: Z80 with SEI80BU decryption, YM3812 and OKI 6295 (sound parts from jotego's JTTOKI)
- Text layer, two 16x16 scroll layers (the background is 6 bpp), 512 sprites with four priority levels
- Checked in simulation against MAME: boot and attract are pixel-identical.

## The V30 CPU model (GPL-2)

The V30 in `hdl/v30` comes from the MiSTer Irem M72 core by Martin Donlon (wickerwaka),
https://github.com/MiSTer-devel/Arcade-IremM72_MiSTer, which is licensed under the GNU General Public License
version 2 (`hdl/v30/LICENSE.GPL-2`). It is used here without asking the author first. This is a free, personal
project; if the author objects to this use, contact TomSVR through this repository and the core will be withdrawn.
`hdl/v30/README.md` lists the changes made to those files.

Build the MRAs with tools/dynduke_build.py from your MAME dynduke.zip.
