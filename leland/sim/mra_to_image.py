"""Build the flat download image an MRA describes (what the MiSTer sends to the core).

usage: python mra_to_image.py game.mra roms_dir out.bin

Handles <part> (hex data, name/offset/length, repeat) and <interleave output="N"> (N = 16..64)
with one-hot hex maps, as Main_MiSTer's mra_loader does: the nonzero nibble at position p
(counted from the right) puts that part on byte lane p of each output unit ("01" = even
bytes, "10" = odd, "00000100" = lane 2 of 8). Files missing from the game's zip are looked up
in its parent sets (offroad for offroadt).
"""
import sys, zipfile, os
import xml.etree.ElementTree as ET

mra, roms, out = sys.argv[1:4]
root = ET.parse(mra).getroot()
rom = root.find('rom')
zips = [rom.get('zip')]
parents = {'offroadt.zip': ['offroad.zip'], 'pigout.zip': [], 'ataxx.zip': [], 'indyheat.zip': [], 'offroad.zip': []}
zips += parents.get(zips[0], [])
zfs = [zipfile.ZipFile(os.path.join(roms, z)) for z in zips]

def load(name):
    for z in zfs:
        if name in z.namelist():
            return z.read(name)
    raise SystemExit('missing ' + name)

def num(v, d=0):
    return int(v, 0) if v else d

def part_bytes(p):
    if p.get('name'):
        data = load(p.get('name'))
        off = num(p.get('offset'))
        n = num(p.get('length'), len(data) - off)
        return data[off:off + n]
    text = (p.text or '').split()
    data = bytes(int(t, 16) for t in text)
    return data * num(p.get('repeat'), 1)

img = bytearray()
for el in rom:
    if el.tag == 'part':
        img += part_bytes(el)
    elif el.tag == 'interleave':
        unit = int(el.get('output')) // 8
        parts = [(int(p.get('map'), 16), part_bytes(p)) for p in el.findall('part')]
        n = len(parts[0][1])
        buf = bytearray(n * unit)
        seen = set()
        for m, b in parts:
            lane = next(i for i in range(unit) if (m >> (4 * i)) & 0xF)
            assert (m >> (4 * lane)) == 1, 'only one-hot maps are supported'
            assert len(b) == n and lane not in seen
            seen.add(lane)
            buf[lane::unit] = b
        assert len(seen) == unit, 'every lane needs a part'
        img += buf
open(out, 'wb').write(img)
print(os.path.basename(mra), len(img), 'bytes')
