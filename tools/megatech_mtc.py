#!/usr/bin/env python3
"""Make Mega-Tech cartridge files (.mtc) for the TomSVR_megatech core's OSD slots 2-8, from your own MAME zips.

Runs on the MiSTer (Scripts menu, or ssh) or on a PC. For every TomSVR Mega-Tech MRA it assembles the cartridge exactly
as MiSTer Main does for the MRA (same parts, same order), from the zips named in the MRA, and writes
"<game>.mtc". A .mtc has the MRA image layout with the BIOS part left empty (the BIOS comes from the MRA you start):
  0x00000 32 kB zero, 0x08000 instruction ROM 32 kB, 0x10000 header 64 kB, 0x20000 game ROM.

usage: megatech_mtc.py [mra_dir] [zip_dir] [out_dir]
defaults (MiSTer): /media/fat/_Arcade/_TomSVR  /media/fat/games/mame  /media/fat/games/Mega-Tech
"""
import sys, os, re, zipfile
import xml.etree.ElementTree as ET

def hexbytes(t):
    return bytes(int(x, 16) for x in re.findall(r'[0-9a-fA-F]{2}', t or ''))

def assemble(rom, zipdir):
    """MiSTer Main mra_loader.cpp rom index 0 assembly (parts, repeat, offset/length, interleave + map)."""
    zips = rom.get('zip').split('|')
    data = bytearray(); romlen = [0] * 8; unit = [1]

    def open_part(name, crc):
        for z in zips:
            p = os.path.join(zipdir, z)
            if not os.path.exists(p): continue
            zf = zipfile.ZipFile(p)
            info = None
            if crc:
                for i in zf.infolist():
                    if i.CRC == int(crc, 16): info = i; break
            if info is None:
                try: info = zf.getinfo(name)
                except KeyError: info = None
            if info is not None: return zf.read(info)
        raise LookupError('%s (crc %s) not found in %s' % (name, crc, ', '.join(zips)))

    def rom_data(buf, mp):
        mp = mp or 1
        idx = 0; m = mp
        while idx < unit[0] and not (m & 0xf): m >>= 4; idx += 1
        offs = []; m = mp; first = True; gaps = 0
        for i in range(unit[0]):
            if m & 0xf: offs.append(idx + (m & 0xf) - 1 + gaps); first = False
            elif not first: gaps += 1
            m >>= 4
        need = romlen[idx] + (len(buf) // len(offs)) * unit[0] + 8
        if len(data) < need: data.extend(b'\0' * (need - len(data)))
        i = 0
        while i < len(buf):
            for o in offs:
                data[romlen[idx] + o] = buf[i]; i += 1
            romlen[idx] += unit[0]

    def do_part(p, mp):
        rep = int(p.get('repeat', '1'), 0)
        if p.get('name'):
            b = open_part(p.get('name'), p.get('crc'))
            off = int(p.get('offset', '0'), 0); ln = int(p.get('length', '-1'), 0)
            b = b[off:] if ln <= 0 else b[off:off + ln]
        else:
            b = hexbytes(p.text)
        for _ in range(rep): rom_data(b, mp)

    first = True
    for el in rom:
        if el.tag == 'part':
            unit[0] = 1
            if first and el.get('name'):      # the BIOS: left empty, saves needing megatech.zip
                rom_data(b'\0' * 0x8000, 0)
            else:
                do_part(el, 0)
            first = False
        elif el.tag == 'interleave':
            unit[0] = int(el.get('output'), 0) // int(el.get('input', '8'), 0)
            for i in range(1, 8): romlen[i] = romlen[0]
            for p in el.findall('part'): do_part(p, int(p.get('map', '0'), 16))
            unit[0] = 1
    return bytes(data[:romlen[0]])

def main():
    a = sys.argv[1:]
    mradir = a[0] if len(a) > 0 else '/media/fat/_Arcade/_TomSVR'
    zipdir = a[1] if len(a) > 1 else '/media/fat/games/mame'
    outdir = a[2] if len(a) > 2 else '/media/fat/games/Mega-Tech'
    os.makedirs(outdir, exist_ok=True)
    ok = bad = 0
    for fn in sorted(os.listdir(mradir)):
        if not fn.endswith('.mra'): continue
        try: root = ET.parse(os.path.join(mradir, fn)).getroot()
        except ET.ParseError: continue
        if (root.findtext('rbf') or '').strip() != 'TomSVR_megatech': continue
        name = (root.findtext('name') or fn[:-4]).replace(' [TomSVR]', '').strip()
        rom = [r for r in root.findall('rom') if r.get('index') == '0'][0]
        try:
            img = assemble(rom, zipdir)
        except LookupError as e:
            print('skip %s: %s' % (name, e)); bad += 1; continue
        safe = re.sub(r'[\\/:*?"<>|]', '_', name)
        with open(os.path.join(outdir, safe + '.mtc'), 'wb') as f: f.write(img)
        print('ok   %s (%d kB)' % (name, len(img) // 1024)); ok += 1
    print('%d cartridges written to %s, %d skipped' % (ok, outdir, bad))

if __name__ == '__main__':
    main()
