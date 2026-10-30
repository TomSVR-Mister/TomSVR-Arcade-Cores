#!/usr/bin/env python3
"""MRA builder for the TomSVR SNES arcade bootleg core (folder snesb, MAME nintendo/snesb.cpp).

usage: snesb_build.py <snesb.cpp> <outdir> [--roms=<dir with MAME zips>] [--check] [setname ...]

Index 0 = 0x200-byte header + the ROM region as MAME loads it (user3, or user7 for the address-scrambled sets),
bytes exactly as in the zips. The core undoes the board's scramble while it writes the ROM to SDRAM, driven by
the header (see snesb/rtl/sb_load.sv):
  000  {ram_size, rom_size}      (stock SNES core MiSTer header: rom_mask = 1 KB << rom_size)
  001  map: 0 LoROM, 1 HiROM     (stock: rom_type)
  010  flags: b0 I/O at 77:0071 DSW1 / 77:0079 COIN, b1 DSW2 at 77:0073, b2 tmntmwb "subtract B9", b3 counter
       (protection: reads return 1, 2, 3...), b4 00:7000-7FFF reads ROM C0:7000-7FFF (sblast2b), b5 WRAM patch
       on load (fill)
011  number of constant reads (max 8)     014-016 counter address (bank, hi, lo)
018-01B RAM window 0: bank, hi, lo, size-1 (max 255) and enable in 01F bit 0 / 01F bit 1 for window 1
01C-01E RAM window 1 base (size = window 0 size)
020-03F 8 constant reads: bank, hi, lo, value
040-05F 8 ROM patches applied while loading: offset (3 bytes, big endian), value
060    number of RAM init writes (after every reset), 061-068: offset/value pairs (window 0)
070-072 WRAM patch: offset (17 bits) / 073 value
080-0BF transform id (0-7) per 64 KB bank of the decoded ROM
0C0-0DF 8 transforms: 3 bytes = output bit k takes input bit sel[k] (3 bits each, k=0 lowest), 1 byte XOR
0E0-0EF data_high[16], 0F0-0FF data_low[16]: byte = data_high[x >> 4] | data_low[x & 15] (before the transform)
100-17F inverse 32 KB block table (source block -> decoded block), 180-1BF inverse low 6 address bits
"""
import os
import re
import sys
import zipfile
from xml.sax.saxutils import escape

HDR = 0x200
MAMEVERSION = '0288'
RBF = 'TomSVR_snesb'
BUTTONS = ('    <buttons names="A,B,X,Y,L,R,Select,Start,Coin" '
           'default="A,B,X,Y,L,R,R2,Start,Select"/>')  # Coin on Select (house rule); SNES Select on R2

# ----------------------------------------------------------------------------------------------------------------
# MAME source parsing


def strip_comments(s):
    s = re.sub(r'/\*.*?\*/', '', s, flags=re.S)
    return re.sub(r'//[^\n]*', '', s)


def num(x):
    x = x.strip().replace("'", '')
    return int(x, 0)


def parse_roms(src):
    """setname -> list of regions: (name, size, flags, [(dest, file, crc, fileoffset, length)])"""
    out = {}
    for m in re.finditer(r'ROM_START\(\s*(\w+)\s*\)(.*?)ROM_END', src, re.S):
        regions = []
        cur = None
        fpos = {}
        last = None
        for line in m.group(2).splitlines():
            line = line.strip()
            r = re.match(r'ROM_REGION(?:16_BE|16_LE)?\(\s*([^,]+),\s*"([^"]+)",\s*([^)]*)\)', line)
            if r:
                cur = [r.group(2), num(r.group(1)), r.group(3), []]
                regions.append(cur)
                continue
            r = re.match(r'ROM_LOAD(16_BYTE)?\(\s*"([^"]+)",\s*([^,]+),\s*([^,]+),\s*(?:BAD_DUMP\s*)?CRC\(([0-9a-f]+)\)', line)
            if r:
                step = 2 if r.group(1) else 1
                last = r.group(2)
                fpos[last] = num(r.group(4))
                cur[3].append((num(r.group(3)), last, r.group(5), 0, num(r.group(4)), step))
                continue
            r = re.match(r'ROM_CONTINUE\(\s*([^,]+),\s*([^)]+)\)', line)
            if r:
                crc = cur[3][-1][2]
                cur[3].append((num(r.group(1)), last, crc, fpos[last], num(r.group(2)), 1))
                fpos[last] += num(r.group(2))
        out[m.group(1)] = regions
    return out


def parse_games(src):
    g = {}
    for m in re.finditer(r'^GAME\(\s*([^,]+),\s*(\w+),\s*(\w+),\s*(\w+),\s*(\w+),\s*\w+,\s*(\w+),\s*\w+,\s*"([^"]*)",'
                         r'\s*"([^"]*)",\s*([^)]*)\)', src, re.M):
        g[m.group(2)] = dict(year=m.group(1).strip(), parent=m.group(3), machine=m.group(4), ports=m.group(5),
                             init=m.group(6), mfr=m.group(7), title=m.group(8), flags=m.group(9))
    return g


def parse_ports(src):
    """INPUT_PORTS name -> {port: [ (mask, name, default, [(value, label)]) ]} with PORT_INCLUDE resolved"""
    blocks = {m.group(1): m.group(2) for m in re.finditer(r'INPUT_PORTS_START\(\s*(\w+)\s*\)(.*?)INPUT_PORTS_END', src, re.S)}
    defs = {'DEF_STR( Coinage )': 'Coinage', 'DEF_STR( Difficulty )': 'Difficulty', 'DEF_STR( Lives )': 'Lives',
            'DEF_STR( Bonus_Life )': 'Bonus Life', 'DEF_STR( Demo_Sounds )': 'Demo Sounds', 'DEF_STR( Free_Play )':
            'Free Play'}

    def label(x):
        x = x.strip()
        if x.startswith('"'):
            return x.strip('"')
        r = re.match(r'DEF_STR\(\s*(\w+)\s*\)', x)
        if r:
            t = r.group(1)
            c = re.match(r'(\d+)C_(\d+)C', t)
            if c:
                return f'{c.group(1)}C/{c.group(2)}C'
            return {'None': 'None', 'Easy': 'Easy', 'Normal': 'Normal', 'Hard': 'Hard', 'Hardest': 'Hardest',
                    'Medium': 'Medium', 'Off': 'Off', 'On': 'On', 'Very_Hard': 'Very Hard', 'Very_Easy': 'Very Easy',
                    'Free_Play': 'Free Play', 'Coinage': 'Coinage', 'Difficulty': 'Difficulty', 'Lives': 'Lives',
                    'Bonus_Life': 'Bonus Life', 'Demo_Sounds': 'Demo Sounds', 'Unused': 'Unused',
                    'Unknown': 'Unknown', 'Language': 'Language', 'English': 'English', 'Japanese': 'Japanese',
                    'Yes': 'Yes', 'No': 'No', 'Coin_A': 'Coin A', 'Coin_B': 'Coin B'}.get(t, t.replace('_', ' '))
        return x

    def parse(name):
        ports = {}
        cur = None
        for line in strip_comments(blocks[name]).splitlines():
            line = line.strip()
            r = re.match(r'PORT_INCLUDE\(\s*(\w+)\s*\)', line)
            if r:
                for k, v in parse(r.group(1)).items():
                    ports[k] = [list(x) for x in v]
                continue
            r = re.match(r'PORT_(?:START|MODIFY)\(\s*"(\w+)"\s*\)', line)
            if r:
                cur = ports.setdefault(r.group(1), [])
                continue
            r = re.match(r'PORT_DIPNAME\(\s*([^,]+),\s*([^,]+),\s*(.+?)\s*\)\s*(?:PORT_|$)', line + ' ')
            if r:
                mask = num(r.group(1))
                cur[:] = [d for d in cur if not d[0] & mask]
                cur.append([mask, label(r.group(3)), num(r.group(2)), []])
                continue
            r = re.match(r'PORT_DIPSETTING\(\s*([^,]+),\s*(.+?)\s*\)\s*(?://|$)', line)
            if r:
                cur[-1][3].append((num(r.group(1)), label(r.group(2))))
        return ports
    return {k: parse(k) for k in blocks}


def parse_arrays(body):
    arr = {}
    for m in re.finditer(r'(\w+)\[[^\]]*\]\s*=\s*\{([^}]*)\}', body):
        arr[m.group(1)] = [int(x, 16) for x in re.findall(r'0x[0-9a-fA-F]+', m.group(2))]
    return arr


def init_body(src, name):
    m = re.search(r'void snesb_state::' + name + r'\(\)\s*\{(.*?)\n\}', src, re.S)
    return m.group(1) if m else ''


# ----------------------------------------------------------------------------------------------------------------
# Per-set board description (from snesb.cpp: init_*, *_map, MACHINE_RESET). Bitswaps are MAME's argument order
# (bit 7 first). 'banks': list of (start, end, bitswap, xor) on the decoded address; one entry may cover all banks.

def bs(*a):
    return tuple(a)


ID = bs(7, 6, 5, 4, 3, 2, 1, 0)


def bank4(b0, b1, b2, b3, rest=None, xors=(0, 0, 0, 0, 0), end=0x400000):
    l = [(0x00000, 0x10000, b0, xors[0]), (0x10000, 0x20000, b1, xors[1]), (0x20000, 0x30000, b2, xors[2]),
         (0x30000, 0x40000, b3, xors[3])]
    if rest:
        l.append((0x40000, end, rest, xors[4]))
    return l


EXTRA = dict(io=True, dsw2=True)
SETS = {
    'kinstb': dict(hirom=1, banks=[(0, 0x400000, bs(5, 0, 6, 1, 7, 4, 3, 2), 0)], **EXTRA, ram=(0x781000, 0x100)),
    'ffight2b': dict(hirom=0, banks=bank4(bs(3, 1, 6, 4, 7, 0, 2, 5), bs(3, 7, 0, 5, 1, 6, 2, 4), bs(1, 7, 6, 4, 5, 2, 3, 0),
                                          bs(0, 3, 2, 5, 4, 6, 7, 1), bs(6, 4, 0, 5, 1, 3, 2, 7), xors=(0xff,) * 5, end=0x140000),
                     patch={0x7ffd: 0x89, 0x7ffc: 0x54}, wram=(0x0adce, 0x00), **EXTRA),
    'ffight3b': dict(hirom=1, banks=[(0, 0x80000, bs(7, 4, 2, 0, 3, 5, 6, 1), 0xff), (0x80000, 0x280000, bs(0, 5, 1, 3, 2, 7, 6, 4), 0),
                                     (0x280000, 0x300000, bs(4, 7, 0, 2, 5, 3, 1, 6), 0xff)],
                     patch={0xfffc: 0x00, 0xfffd: 0xfe, 0xfe33: 0x5c, 0xfe34: 0x00, 0xfe35: 0x00, 0xfe36: 0xc0, 0xfeab: 0x60}, **EXTRA),
    'iron': dict(hirom=0, banks=[(0, 0x80000, bs(2, 7, 1, 6, 3, 0, 5, 4), 0xff), (0x80000, 0x140000, bs(6, 3, 0, 5, 1, 4, 7, 2), 0)], **EXTRA),
    'denseib': dict(hirom=1, banks=bank4(bs(1, 7, 0, 6, 3, 4, 5, 2), bs(3, 4, 7, 2, 0, 6, 5, 1), bs(5, 4, 2, 1, 7, 0, 6, 3),
                                         bs(0, 1, 3, 7, 2, 6, 5, 4), bs(4, 5, 1, 0, 2, 3, 7, 6), xors=(0xff,) * 5, end=0x200000),
                    patch={0xfffc: 0x40, 0xfffd: 0xf7}, **EXTRA),
    'legendsb': dict(hirom=0, banks=bank4(bs(6, 5, 4, 2, 1, 0, 3, 7), bs(6, 1, 3, 5, 2, 0, 7, 4), bs(2, 6, 3, 0, 4, 5, 7, 1),
                                          bs(5, 4, 2, 7, 0, 3, 6, 1), bs(3, 6, 0, 5, 1, 4, 7, 2), xors=(0xff,) * 5, end=0x100000),
                     patch={0x7ffc: 0x19, 0x7ffd: 0x80}, **EXTRA),
    # address + data scrambled (tables parsed from the driver)
    'denseib2': dict(hirom=1, scr='init_denseib2', n=0x200000,
                     banks=bank4(bs(2, 1, 3, 0, 7, 4, 5, 6), bs(1, 7, 4, 5, 6, 0, 3, 2), bs(0, 2, 6, 7, 5, 3, 4, 1), bs(6, 5, 0, 3, 1, 7, 2, 4),
                                 xors=(0xff, 0, 0xff, 0xff)), patch={0xfffc: 0x40, 0xfffd: 0xf7}, **EXTRA),
    'sblast2b': dict(hirom=1, scr='init_sblast2b', n=0x180000,
                     banks=bank4(bs(6, 3, 5, 4, 2, 0, 7, 1), bs(4, 0, 7, 6, 3, 1, 2, 5), bs(5, 7, 6, 1, 4, 3, 0, 2), bs(3, 1, 2, 0, 5, 6, 4, 7),
                                 xors=(0xff, 0xff, 0, 0xff)), patch={0xfffc: 0xc0, 0xfffd: 0x7a}, io=True, dsw2=True,
                     consts=[(0x6a626f, 0xb1), (0x6a63e0, 0x9e), (0x6a65c8, 0xf4), (0x6a694b, 0x3a), (0x6a6d1a, 0xc5), (0x6a6fb7, 0x47)],
                     counter=0x75bd37, mirror7=True),
    'endless': dict(hirom=0, scr='init_endless', n=0x200000,
                    banks=bank4(bs(2, 3, 4, 1, 7, 0, 6, 5), bs(1, 5, 6, 0, 2, 4, 7, 3), bs(3, 0, 1, 6, 4, 5, 2, 7), bs(0, 4, 2, 3, 5, 6, 7, 1),
                                xors=(0, 0xff, 0, 0xff)), patch={0x7ffc: 0x00, 0x7ffd: 0x80}, **EXTRA,
                    consts=[(0x5802bc, 0xb4), (0x58036a, 0x8a), (0x5807c1, 0xd9), (0x580956, 0xa5), (0x580e83, 0x6b),
                            (0x00800b, 0x50), (0x00800c, 0xe8)],
                    counter=0x624b7f, ram=(0x781000, 0x22), ram2=0x781200),
    'rushbets': dict(hirom=1, scr='init_rushbets', n=0x200000, bit20=True,
                     banks=bank4(bs(0, 7, 6, 3, 5, 4, 1, 2), bs(2, 1, 3, 7, 6, 5, 4, 0), bs(4, 6, 0, 2, 7, 3, 5, 1), bs(5, 4, 7, 1, 0, 6, 2, 3),
                                 xors=(0xff, 0xff, 0, 0xff)), patch={0xfffc: 0xec, 0xfffd: 0x80}, io=True, dsw2=False,
                     consts=[(0x75af49, 0xe3), (0x75a05a, 0xf4), (0x75a16b, 0x05), (0x75a27c, 0x16), (0x75a38d, 0x27)],
                     counter=0x5b8e3c, ram=(0x785000, 0x10)),
    'tmntmwb': dict(hirom=0, scr='init_tmntmwb', n=0x200000, sub=True,
                    banks=bank4(bs(6, 1, 3, 0, 7, 2, 4, 5), bs(7, 3, 1, 2, 5, 4, 6, 0), bs(0, 4, 5, 6, 1, 2, 7, 3), bs(1, 2, 6, 3, 4, 5, 0, 7),
                                xors=(0xff, 0xff, 0, 0xff)), patch={0x7ffc: 0x72, 0x7ffd: 0xff}, **EXTRA,
                    consts=[(0x7103cd, 0x8c), (0x7103ce, 0x8c), (0x7065f0, 0x31), (0x7065f1, 0x31), (0x7132cc, 0x5a), (0x7132cd, 0x5a),
                            (0x7010f1, 0x47), (0x7010f2, 0x47)], ram=(0x781000, 0x100)),
    'venom': dict(hirom=0, scr='init_venom', n=0x300000,
                  banks=bank4(bs(6, 7, 0, 3, 1, 4, 2, 5), bs(0, 1, 4, 5, 3, 7, 6, 2), bs(1, 3, 2, 6, 5, 4, 0, 7), bs(4, 0, 7, 6, 2, 1, 5, 3),
                              xors=(0xff, 0, 0xff, 0)), patch={0x7ffc: 0x98, 0x7ffd: 0xff}, **EXTRA, ram=(0x781000, 0x22), ram2=0x781200),
    'wldgunsb': dict(hirom=0, scr='init_wldgunsb', n=0x100000,
                     banks=bank4(bs(3, 1, 7, 0, 6, 4, 5, 2), bs(4, 7, 3, 2, 0, 1, 6, 5), bs(6, 0, 7, 1, 4, 3, 5, 2), bs(0, 2, 6, 4, 1, 5, 7, 3),
                                 xors=(0xff, 0, 0xff, 0)), patch={0x7ffc: 0x40, 0x7ffd: 0x80}, **EXTRA,
                     consts=[(0x721197, 0xe4), (0x722262, 0x2b), (0x723363, 0x93), (0x72443a, 0x66), (0x72553b, 0xbf)],
                     counter=0x7bf45b, ram=(0x781000, 0x22), raminit=[(0x10, 9), (0x12, 0)]),
    'issdxb': dict(hirom=0, scr='init_issdxb', n=0x200000, bit20=True,
                   banks=bank4(bs(4, 5, 1, 6, 0, 3, 7, 2), bs(0, 2, 3, 7, 4, 5, 6, 1), bs(5, 7, 6, 4, 1, 0, 2, 3), bs(6, 3, 0, 1, 2, 4, 5, 7),
                               xors=(0xff, 0xff, 0, 0xff)), patch={0x7ffc: 0x00, 0x7ffd: 0x80}, **EXTRA,
                   consts=[(0x5b0956, 0xd3), (0x5b134a, 0x69), (0x5b2c8f, 0xb6),
                           # the game reads these as 16-bit words; MAME maps only the low byte, so the high
                           # byte is open bus = 5B (the bank byte just fetched). The ROM there broke kick-off.
                           (0x5b0957, 0x5b), (0x5b134b, 0x5b), (0x5b2c90, 0x5b)],
                   counter=0x6a6d1d, ram=(0x781000, 0x14)),
}
SETS['ffight3b2'] = SETS['ffight3b']
SETS['endlessa'] = SETS['endless']
PHASE1 = ['kinstb', 'iron', 'ffight2b', 'denseib', 'legendsb']


# ----------------------------------------------------------------------------------------------------------------
# images

def region_image(regions, name, zipdata):
    for rn, size, flags, loads in regions:
        if rn != name:
            continue
        img = bytearray(b'\xff' * size if 'ERASEFF' in flags else b'\0' * size)
        for dest, f, crc, foff, length, step in loads:
            d = zipdata[crc][foff:foff + length]
            img[dest:dest + len(d)] = d
        return img
    return None


def region_parts(regions, name, zipname):
    """MRA parts that lay the region out in order (ROM_LOAD / ROM_CONTINUE chunks sorted by destination)"""
    for rn, size, flags, loads in regions:
        if rn != name:
            continue
        chunks = sorted((dest, f, crc, foff, length) for dest, f, crc, foff, length, step in loads)
        parts, pos = [], 0
        fill = 'FF' if 'ERASEFF' in flags else '00'
        for dest, f, crc, foff, length in chunks:
            if dest > pos:
                parts.append(f'        <part repeat="0x{dest - pos:X}">{fill}</part>')
            a = f' offset="0x{foff:X}" length="0x{length:X}"' if (foff or length != None) else ''
            parts.append(f'        <part zip="{zipname}" name="{f}" crc="{crc}" offset="0x{foff:X}" length="0x{length:X}"/>')
            pos = dest + length
        return parts, pos
    return None, 0


def bitswap(v, sel):            # sel = MAME argument order (bit 7 first)
    o = 0
    for k, s in enumerate(reversed(sel)):
        o |= ((v >> s) & 1) << k
    return o


def mame_reference(src, name, cfg, img):
    """MAME's init_* for this set, literally (img = the source region: user3, or user7 for scrambled sets)"""
    out = bytearray(img)
    if 'scr' in cfg:
        a = parse_arrays(init_body(src, cfg['scr']))
        ath, atl, dh, dl = a['address_tab_high'], a['address_tab_low'], a['data_high'], a['data_low']
        n = cfg['n']
        size = len(img) if name != 'issdxb' else 0x300000
        out = bytearray(b'\xff' * size)
        for i in range(n):
            if cfg.get('bit20'):
                j = (ath[(i >> 15) & 0x1f] << 15) + (i & 0x107fc0) + atl[i & 0x3f]
            else:
                j = (ath[i >> 15] << 15) + (i & 0x7fc0) + atl[i & 0x3f]
            x = img[j]
            if cfg.get('sub') and not i & 0x1000:
                x = (x - 0xb9) & 0xff
            x = dh[x >> 4] | dl[x & 15]
            for s, e, sel, xo in cfg['banks']:
                if s <= i < e and i < 0x40000:
                    x = bitswap(x, sel) ^ xo
            out[i] = x
    else:
        for i in range(len(out)):
            for s, e, sel, xo in cfg['banks']:
                if s <= i < e:
                    out[i] = bitswap(out[i], sel) ^ xo
                    break
    for k, v in cfg.get('patch', {}).items():
        out[k] = v
    return out


def preimage(src, cfg, want=0xff):
    """source byte that the board's nibble tables turn into `want` (for padding past the dumped ROMs)"""
    if 'scr' not in cfg:
        return want
    a = parse_arrays(init_body(src, cfg['scr']))
    for x in range(256):
        if a['data_high'][x >> 4] | a['data_low'][x & 15] == want:
            return x
    raise SystemExit('no pre-image for %02x' % want)


def header(src, name, cfg, romsize):
    h = bytearray(HDR)
    rs = max(1, (romsize - 1).bit_length() - 10)                # 1 KB << rs >= romsize
    h[0] = rs
    h[1] = cfg['hirom']
    f = 0
    f |= 1 if cfg.get('io') else 0
    f |= 2 if cfg.get('dsw2') else 0
    f |= 4 if cfg.get('sub') else 0
    f |= 8 if 'counter' in cfg else 0
    f |= 16 if cfg.get('mirror7') else 0
    f |= 32 if 'wram' in cfg else 0
    h[0x10] = f
    consts = cfg.get('consts', [])
    assert len(consts) <= 8
    h[0x11] = len(consts)
    c = cfg.get('counter', 0)
    h[0x14:0x17] = c.to_bytes(3, 'big')
    if 'ram' in cfg:
        base, size = cfg['ram']
        assert size <= 0x100
        h[0x18:0x1b] = base.to_bytes(3, 'big')
        h[0x1b] = size - 1
        h[0x1f] |= 1
    if 'ram2' in cfg:
        h[0x1c:0x1f] = cfg['ram2'].to_bytes(3, 'big')
        h[0x1f] |= 2
    for k, (a, v) in enumerate(consts):
        h[0x20 + 4 * k:0x24 + 4 * k] = a.to_bytes(3, 'big') + bytes([v])
    patch = sorted(cfg.get('patch', {}).items())
    assert len(patch) <= 8
    h[0x12] = len(patch)
    for k, (a, v) in enumerate(patch):
        h[0x40 + 4 * k:0x44 + 4 * k] = a.to_bytes(3, 'big') + bytes([v])
    ri = cfg.get('raminit', [])
    h[0x60] = len(ri)
    for k, (o, v) in enumerate(ri):
        h[0x61 + 2 * k:0x63 + 2 * k] = bytes([o, v])
    if 'wram' in cfg:
        o, v = cfg['wram']
        h[0x70:0x73] = o.to_bytes(3, 'big')
        h[0x73] = v
    # transforms: id 0 = identity
    tr = [(ID, 0)]
    for s, e, sel, xo in cfg['banks']:
        if (sel, xo) not in tr:
            tr.append((sel, xo))
        t = tr.index((sel, xo))
        for b in range(s >> 16, min(e, 0x400000 if 'scr' not in cfg else 0x40000) + 0xffff >> 16):
            h[0x80 + b] = t
    assert len(tr) <= 8
    for t, (sel, xo) in enumerate(tr):
        packed = 0
        for k, s in enumerate(reversed(sel)):
            packed |= s << (3 * k)
        h[0xc0 + 4 * t:0xc3 + 4 * t] = packed.to_bytes(3, 'little')
        h[0xc3 + 4 * t] = xo
    if 'scr' in cfg:
        a = parse_arrays(init_body(src, cfg['scr']))
        ath, atl, dh, dl = a['address_tab_high'], a['address_tab_low'], a['data_high'], a['data_low']
        fwd = {}
        for k in range(128):
            if cfg.get('bit20'):
                fwd[k] = ath[k & 0x1f] | (k & 0x20)
            elif k < len(ath):
                fwd[k] = ath[k]
        inv = [0xff] * 128
        for k, j in fwd.items():
            if k * 0x8000 < cfg['n']:
                assert inv[j] == 0xff, (name, k, j)
                inv[j] = k
        for j in range(128):
            if inv[j] == 0xff:
                inv[j] = j if j not in fwd.values() else 0x7f
        h[0x100:0x180] = bytes(inv)
        il = [0] * 64
        assert sorted(atl) == list(range(64))
        for k, j in enumerate(atl):
            il[j] = k
        h[0x180:0x1c0] = bytes(il)
        h[0xe0:0xf0] = bytes(dh)
        h[0xf0:0x100] = bytes(dl)
    else:
        h[0x100:0x180] = bytes(range(128))
        h[0x180:0x1c0] = bytes(range(64))
        h[0xe0:0xf0] = bytes(x << 4 for x in range(16))
        h[0xf0:0x100] = bytes(range(16))
    return h


def core_model(h, src_img, out_size):
    """What sb_load.sv does: each source byte j goes to its decoded address i with the decoded value"""
    out = bytearray(b'\x5a' * out_size)   # SDRAM keeps whatever was there before: every byte must be written
    flags = h[0x10]
    tr = []
    for t in range(8):
        p = int.from_bytes(h[0xc0 + 4 * t:0xc3 + 4 * t], 'little')
        tr.append(([(p >> (3 * k)) & 7 for k in range(8)], h[0xc3 + 4 * t]))
    patches = {int.from_bytes(h[0x40 + 4 * k:0x43 + 4 * k], 'big'): h[0x43 + 4 * k] for k in range(h[0x12])}
    for j, x in enumerate(src_img):
        i = (h[0x100 + (j >> 15 & 0x7f)] << 15) | (j & 0x7fc0) | h[0x180 + (j & 0x3f)]
        if j >> 22:
            continue
        if flags & 4 and not i & 0x1000:
            x = (x - 0xb9) & 0xff
        x = h[0xe0 + (x >> 4)] | h[0xf0 + (x & 15)]
        sel, xo = tr[h[0x80 + (i >> 16 & 0x3f)]]
        x = sum(((x >> sel[k]) & 1) << k for k in range(8)) ^ xo
        if i in patches:
            x = patches[i]
        if i < out_size:
            out[i] = x
    return out


# ----------------------------------------------------------------------------------------------------------------
# MRA

def dip_xml(ports, game):
    blocks = []
    defaults = []
    for pi, pn in enumerate(['DSW1', 'DSW2']):
        p = ports.get(pn, [])
        d = 0xff
        for mask, nm, dflt, settings in p:
            d = (d & ~mask) | dflt
            if not settings or nm in ('Unused', 'Unknown'):
                continue
            lo = (mask & -mask).bit_length() - 1
            hi = mask.bit_length() - 1
            assert mask == ((1 << (hi + 1)) - (1 << lo)), (game, pn, hex(mask))
            ids = []
            for v in range(1 << (hi - lo + 1)):
                lab = [l for val, l in settings if val == v << lo]
                ids.append(lab[0] if lab else f'{v << lo:02X}h')
            bits = f'{pi * 8 + lo}' if hi == lo else f'{pi * 8 + lo},{pi * 8 + hi}'
            ids = ','.join(escape(i.replace(',', ' '), {'"': '&quot;'}) for i in ids)
            blocks.append(f'        <dip name="{escape(nm)}" bits="{bits}" ids="{ids}"/>')
        defaults.append(f'{d:02X}')
    return blocks, ','.join(defaults)


def make_mra(name, game, cfg, regions, ports, zipname, check_zip=None):
    rn = 'user7' if 'scr' in cfg else 'user3'
    parts, size = region_parts(regions, rn, zipname)
    full = [r[1] for r in regions if r[0] == 'user3'][0]
    if 'scr' in cfg and full > size:     # MAME region larger than the dumps (ERASEFF): fill it, it decodes to FF
        parts.append(f'        <part repeat="0x{full - size:X}">{preimage(SRC, cfg):02X}</part>')
        size = full
    h = header(SRC, name, cfg, size if 'scr' not in cfg else ({'issdxb': 0x300000}.get(name, size)))
    dips, dflt = dip_xml(ports, name)
    year = game['year'] if '?' not in game['year'] else '199?'
    zips = zipname if game['parent'] == '0' else f'{name}.zip|{game["parent"]}.zip'
    title = game['title'].replace(' (SNES bootleg)', '').replace(' (SNES bootleg, ', ' (')
    title = title.replace(': ', ' - ')   # no ':' in FAT/exFAT file names (MiSTer SD)
    for ch in '\\/*?"<>|':
        title = title.replace(ch, '')
    flags = game['flags'].replace('MACHINE_', '').replace(' | ', ', ').lower()
    out = [
        f'<!-- MAME {name} (nintendo/snesb.cpp): {escape(game["title"])}. MAME status: {flags}. -->',
        '<misterromdescription>',
        f'    <name>{escape(title)} [TomSVR]</name>',
        f'    <setname>{name}</setname>',
        '    <rotation>horizontal</rotation>',
        f'    <mameversion>{MAMEVERSION}</mameversion>',
        f'    <year>{year}</year>',
        f'    <manufacturer>{escape(game["mfr"])}</manufacturer>',
        '    <players>2</players>',
        f'    <rbf>{RBF}</rbf>',
        '    <joystick>8</joystick>',
        f'    <switches page_id="1" page_name="Switches" base="16" default="{dflt}">',
        *dips,
        '    </switches>',
        f'    <rom index="0" zip="{zips}" md5="None">',
        *[f'        <part>{" ".join("%02X" % b for b in h[i:i + 16])}</part>' for i in range(0, HDR, 16)],
        *parts,
        '    </rom>',
        BUTTONS,
        '</misterromdescription>', '']
    return '\n'.join(out), title


def main():
    global SRC
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    opts = dict(a[2:].split('=', 1) if '=' in a else (a[2:], '1') for a in sys.argv[1:] if a.startswith('--'))
    SRC = strip_comments(open(args[0]).read())
    outdir = args[1]
    want = args[2:] or PHASE1
    regions_all = parse_roms(SRC)
    games = parse_games(SRC)
    ports_all = parse_ports(SRC)
    os.makedirs(outdir, exist_ok=True)
    for name in want:
        cfg, game = SETS[name], games[name]
        zipname = f'{name}.zip' if game['parent'] == '0' else f'{game["parent"]}.zip'
        mra, title = make_mra(name, game, cfg, regions_all[name], ports_all[game['ports']], zipname)
        fn = os.path.join(outdir, f'{title} [TomSVR].mra')
        open(fn, 'w').write(mra)
        print('wrote', fn)
        if 'roms' in opts:
            zd = {}
            for z in [f'{name}.zip'] + ([f'{game["parent"]}.zip'] if game['parent'] != '0' else []):
                p = os.path.join(opts['roms'], z)
                if os.path.exists(p):
                    zz = zipfile.ZipFile(p)
                    for i in zz.infolist():
                        zd['%08x' % i.CRC] = zz.read(i)
            rn = 'user7' if 'scr' in cfg else 'user3'
            img = region_image(regions_all[name], rn, zd)
            img = img[:region_parts(regions_all[name], rn, zipname)[1]]   # what the MRA loads from the zips
            full = [r[1] for r in regions_all[name] if r[0] == 'user3'][0]
            if 'scr' in cfg and full > len(img):
                img = img + bytes([preimage(SRC, cfg)]) * (full - len(img))
            ref = mame_reference(SRC, name, cfg, img)
            h = header(SRC, name, cfg, len(ref))
            mod = core_model(h, img, len(ref))
            bad = sum(a != b for a, b in zip(ref, mod))
            print(f'   {name}: decoded {len(ref):#x} bytes, core model vs MAME init: {"MATCH" if not bad else f"{bad} DIFF"}')
            if 'dump' in opts:
                open(os.path.join(outdir, f'{name}.ref.bin'), 'wb').write(ref)
                open(os.path.join(outdir, f'{name}.src.bin'), 'wb').write(bytes(h) + img)


if __name__ == '__main__':
    main()
