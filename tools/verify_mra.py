#!/usr/bin/env python3
"""Re-implementation of MiSTer Main mra_loader.cpp rom index 0 assembly, to check an MRA offline.
usage: verify_mra.py file.mra zipdir expected_md5_file"""
import sys, zipfile, zlib, hashlib, re, os
import xml.etree.ElementTree as ET

mra, zipdir = sys.argv[1], sys.argv[2]
root = ET.parse(mra).getroot()
rom = [r for r in root.findall('rom') if r.get('index') == '0'][0]
zips = rom.get('zip').split('|')

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
        if info is not None:
            return zf.read(info), z, info.filename
    raise SystemExit('part not found: %s %s' % (name, crc))

def hexbytes(t):
    return bytes(int(x, 16) for x in re.findall(r'[0-9a-fA-F]{2}', t or ''))

data = bytearray(); romlen = [0] * 8; unitlen = 1
def rom_data(buf, mp):
    global data
    mp = mp or 1
    idx = 0; m = mp
    while idx < unitlen and not (m & 0xf): m >>= 4; idx += 1
    offs = []; m = mp; first = True; gaps = 0
    for i in range(unitlen):
        if m & 0xf: offs.append(idx + (m & 0xf) - 1 + gaps); first = False
        elif not first: gaps += 1
        m >>= 4
    i = 0
    need = romlen[idx] + (len(buf) // len(offs)) * unitlen + 8
    if len(data) < need: data.extend(b'\0' * (need - len(data)))
    while i < len(buf):
        for o in offs:
            data[romlen[idx] + o] = buf[i]; i += 1
        romlen[idx] += unitlen

used = []
def do_part(p, mp):
    rep = int(p.get('repeat', '1'), 0)
    if p.get('name'):
        b, z, fn = open_part(p.get('name'), p.get('crc'))
        off = int(p.get('offset', '0'), 0); ln = int(p.get('length', '-1'), 0)
        b = b[off:] if ln <= 0 else b[off:off + ln]
        used.append((p.get('name'), z, fn))
    else:
        b = hexbytes(p.text)
    for _ in range(rep): rom_data(b, mp)

patches = []
for el in rom:
    if el.tag == 'part':
        unitlen = 1; do_part(el, 0)
    elif el.tag == 'interleave':
        unitlen = int(el.get('output'), 0) // int(el.get('input', '8'), 0)
        for i in range(1, 8): romlen[i] = romlen[0]
        for p in el.findall('part'):
            do_part(p, int(p.get('map', '0'), 16))
        unitlen = 1
    elif el.tag == 'patch':
        patches.append((int(el.get('offset'), 0), hexbytes(el.text)))
final = bytearray(data[:romlen[0]])
for off, b in patches:
    assert off + len(b) <= len(final)
    final[off:off + len(b)] = b
if os.environ.get("VDUMP"): open(os.environ["VDUMP"],"wb").write(final)
md5 = hashlib.md5(final).hexdigest()
print('assembled', hex(len(final)), 'bytes, md5', md5)
for u in sorted(set(used)): print('  used', u)
if len(sys.argv) > 3:
    exp = open(sys.argv[3]).read().strip()
    print('expected md5', exp, 'MATCH' if exp == md5 else 'MISMATCH')
    if len(sys.argv) > 4:
        open(sys.argv[4], 'wb').write(final)
