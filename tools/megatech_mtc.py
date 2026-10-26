#!/usr/bin/env python3
"""Make Mega-Tech cartridge files (.mtc) for the TomSVR_megatech core's OSD slots 2-8, and Mega Play cartridge files
(.mpc) for the TomSVR_megaplay core's OSD slots 2-4, from your own MAME zips.

Runs on the MiSTer (Scripts menu, or ssh) or on a PC. For every TomSVR Mega-Tech MRA it assembles the cartridge exactly
as MiSTer Main does for the MRA (same parts, same order), from the zips named in the MRA, and writes
"<game>.mtc". A .mtc has the MRA image layout with the BIOS part left empty (the BIOS comes from the MRA you start):
  0x00000 32 kB zero, 0x08000 instruction ROM 32 kB, 0x10000 header 64 kB, 0x20000 game ROM.
A .mpc is the same for Mega Play: 0x000000 128 kB zero, 0x020000 instruction ROM 32 kB, 0x028000 header 32 kB
(byte 2 = the game's DIP switch nibble, the MRA's default), 0x030000 game ROM.

usage: megatech_mtc.py [mra_dir] [zip_dir] [out_dir]
defaults (MiSTer): /media/fat/_Arcade (searched with its subfolders)  /media/fat/games/mame  /media/fat/games/Mega-Tech
The .mpc files go to the folder "Mega Play" next to out_dir (/media/fat/games/Mega Play).
"""
import sys, os, re, zipfile
import xml.etree.ElementTree as ET

def hexbytes(t):
    return bytes(int(x, 16) for x in re.findall(r'[0-9a-fA-F]{2}', t or ''))

def assemble(rom, zipdir, bios_size=0x8000):
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
                rom_data(b'\0' * bios_size, 0)
            else:
                do_part(el, 0)
            first = False
        elif el.tag == 'interleave':
            unit[0] = int(el.get('output'), 0) // int(el.get('input', '8'), 0)
            for i in range(1, 8): romlen[i] = romlen[0]
            for p in el.findall('part'): do_part(p, int(p.get('map', '0'), 16))
            unit[0] = 1
    return bytes(data[:romlen[0]])

def find_mras(top):
    """MRA files under top that name the TomSVR_megatech core (cheap text check before any XML parsing).
    Skips the arcade organizer's _Organized trees (links to the same MRAs) and core/ROM folders."""
    for d, dirs, files in os.walk(top):
        dirs[:] = [x for x in dirs if x.lower() not in ('cores', 'mame', 'hbmame', 'mra_backup')
                   and not x.lower().startswith('_organized')]
        for fn in sorted(files):
            if not fn.lower().endswith('.mra'): continue
            path = os.path.join(d, fn)
            try:
                with open(path, 'rb') as f: head = f.read(4096)
            except OSError: continue
            if b'tomsvr_megatech' in head.lower() or b'tomsvr_megaplay' in head.lower(): yield path

def main():
    a = sys.argv[1:]
    mradir = a[0] if len(a) > 0 else '/media/fat/_Arcade'
    zipdir = a[1] if len(a) > 1 else '/media/fat/games/mame'
    outdir = a[2] if len(a) > 2 else '/media/fat/games/Mega-Tech'
    print('MRAs: %s (and subfolders)\nzips: %s\nout:  %s' % (mradir, zipdir, outdir))
    if not os.path.isdir(zipdir): print('zip folder not found: %s' % zipdir)
    print('searching for Mega-Tech MRAs...'); sys.stdout.flush()
    os.makedirs(outdir, exist_ok=True)
    ok = bad = seen = mt = 0; done = set()
    for path in find_mras(mradir):
        seen += 1
        try: root = ET.parse(path).getroot()
        except Exception as e:
            if 'mega-tech' in path.lower(): print('cannot read %s: %s' % (path, e))
            continue
        rbf = (root.findtext('rbf') or '').strip().lower()
        mp = rbf.startswith('tomsvr_megaplay')
        if not (mp or rbf.startswith('tomsvr_megatech')): continue
        mt += 1
        name = (root.findtext('name') or os.path.basename(path)[:-4]).replace(' [TomSVR]', '').strip()
        if name in done: continue
        roms = [r for r in root.findall('rom') if r.get('index') == '0']
        if not roms: continue
        try:
            img = assemble(roms[0], zipdir, 0x20000 if mp else 0x8000)
            if mp:     # header byte 2 = the game's DSW nibble (MRA switches default, second byte, low nibble)
                sw = root.find('switches'); d = (sw.get('default') if sw is not None else '') or ''
                d = [int(x, 16) for x in d.split(',') if x.strip()]
                img = bytearray(img); img[0x28002] = (d[1] & 0xf) if len(d) > 1 else 0xf; img = bytes(img)
        except Exception as e:
            print('skip %s: %s' % (name, e)); bad += 1; continue
        safe = re.sub(r'[\\/:*?"<>|]', '_', name)
        od = os.path.join(os.path.dirname(os.path.abspath(outdir)), 'Mega Play') if mp else outdir
        os.makedirs(od, exist_ok=True)
        with open(os.path.join(od, safe + ('.mpc' if mp else '.mtc')), 'wb') as f: f.write(img)
        print('ok   %s (%d kB)' % (name, len(img) // 1024)); ok += 1; done.add(name)
    print('%d Mega-Tech / Mega Play MRAs found' % mt)
    print('%d cartridges written, %d skipped' % (ok, bad))

if __name__ == '__main__':
    main()
