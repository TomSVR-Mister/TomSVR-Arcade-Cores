#!/usr/bin/env python3
"""Generic Comad -> jtgals port library. A game config script imports this."""
import struct, os, json, zlib, hashlib, subprocess, re

BASE = os.path.dirname(os.path.abspath(__file__))   # tools/port
ROMS = os.environ.get('COMAD_ROMS', os.path.join(BASE, 'roms'))   # unpacked MAME ROM folders (not in the repo)
SHADOW, FLAGS, MARK = 0x53c400, 0x53c100, 0x53c300
# COMAD=1: build for the jtcomad fork (not a beta core). CPU ROM 000000-4FFFFF = image 000000-4FFFFF,
# extension ROM CPU B00000-BFFFFF = image 500000-5FFFFF, OKI at A80001.
COMAD = os.environ.get('COMAD') == '1'
ROMSIZE = 0x600000 if COMAD else 0x400000
EXT = 0x500000                       # image offset of the extension ROM (COMAD only)
OKIA = 0xa80001 if COMAD else 0x400001
def cpu_addr(a): return a - EXT + 0xb00000 if COMAD and a >= EXT else a
OUT = os.environ.get('COMAD_OUT', os.path.join(BASE, 'out_comad' if COMAD else 'out'))
CORE = 'jtcomad' if COMAD else 'jtgals'
L = lambda v: struct.pack('>I', v)

def rd(p): return open(os.path.join(ROMS, p), 'rb').read()
def crc(p): return '%08x' % (zlib.crc32(rd(p)) & 0xffffffff)

class Port:
    def __init__(self, name, banks, size):
        """banks: list of (base, kind, files): kind 'il' -> (even, odd) byte-interleaved, 'ws' -> word-swapped 16-bit file"""
        self.name, self.banks = name, banks
        self.src = bytearray(b'\xff' * size)
        for base, kind, f in banks:
            if kind == 'il':
                e, o = rd(f[0]), rd(f[1]); n = len(e)
                self.src[base:base + 2 * n:2] = e; self.src[base + 1:base + 2 * n:2] = o
            else:
                w = rd(f); b = bytearray(w); b[0::2], b[1::2] = w[1::2], w[0::2]
                self.src[base:base + len(b)] = b
        self.patches = {}
        self.log = []

    # ------------------------------------------------------------- layout
    def set_layout(self, layout):
        layout = list(layout)
        end = sum(n for _, _, n in layout)
        if COMAD and end < ROMSIZE: layout.append((end, None, ROMSIZE - end))   # pad (4 MB builds, empty extension)
        self.layout = layout
        self.img = bytearray(b'\xff' * ROMSIZE)
        pos = 0
        for dst, s, n in layout:
            assert dst == pos, (hex(dst), hex(pos))
            if s is not None: self.img[dst:dst + n] = self.src[s:s + n]
            pos = dst + n
        assert pos == ROMSIZE, hex(pos)
        self.unpatched = bytes(self.img)

    def identity_layout(self):
        n = min(len(self.src), ROMSIZE)
        lay = [(0, 0, n)]
        if n < ROMSIZE: lay.append((n, None, ROMSIZE - n))
        self.set_layout(lay)

    def put(self, a, data, why='', force=False):
        for i, b in enumerate(data):
            if not force and a + i in self.patches and self.patches[a + i] != b: raise SystemExit('conflict at %x (%s)' % (a + i, why))
            self.patches[a + i] = b; self.img[a + i] = b
    def getl(self, a): return struct.unpack('>I', self.img[a:a + 4])[0]
    def getw(self, a): return struct.unpack('>H', self.img[a:a + 2])[0]
    def find(self, pat, lo=0, hi=0x100000):
        r = []; i = self.img.find(pat, lo, hi)
        while i >= 0: r.append(i); i = self.img.find(pat, i + 1, hi)
        return r

    # ------------------------------------------------------------- reference relocation
    DESYNC_OK = re.compile(r'^(lea|move|movea|cmp|tst|clr|btst|bset|bclr|bchg|add|sub|and|or|eor|neg|not|jsr|jmp|pea|mul|div)')
    def relocate(self, refs_json, mapper, label, skip=(), data_patch=(), coords=True):
        refs = json.load(open(os.path.join(BASE, refs_json))); n = 0
        for r in refs:
            if r['lab'] != label: continue
            j, v = r['j'], r['v']
            if j in skip: continue
            if r['cls'] == 'data' and j not in data_patch: continue
            if r['cls'] == 'desync':
                t = r['insn'].split(' ', 1)[1]
                if not self.DESYNC_OK.match(t) or ('#%d' % v) in t and not t.startswith(('moveal', 'movel', 'lea', 'cmpal')):
                    continue
            if coords and self.getw(j - 2) == 0x2c7c and (v & 0xff00) == 0:
                continue                               # movea.l #$00XX00YY,a6 : text coordinates
            assert self.getl(j) == v, hex(j)
            m = mapper(v)
            if m is None: raise SystemExit('%s value %08x at %06x not mapped' % (label, v, j))
            self.put(j, L(m), label); n += 1
        self.log.append('%s refs relocated: %d' % (label, n))

    def patch_pattern(self, pat, repl, offset=0, count=None, why=''):
        hits = self.find(bytes.fromhex(pat))
        if count is not None: assert len(hits) == count, (why, [hex(h) for h in hits])
        for h in hits: self.put(h + offset, bytes.fromhex(repl), why)
        self.log.append('%s: %d' % (why, len(hits)))
        return hits

    # ------------------------------------------------------------- sprite converter
    def converter(self, hook, copyfn, ofs1, ofs2, addr=0x7f000, yoff=15, irq4fn=0, bufs=None, pad=b'\xff'):
        args = ['m68k-linux-gnu-as', '-m68000']
        for k, v in dict(OFS1=ofs1, OFS2=ofs2, YOFF=yoff, COPYFN=copyfn, IRQ4FN=irq4fn, **(bufs or {})).items(): args += ['--defsym', '%s=%d' % (k, v)]
        o = f'{BASE}/asm/{self.name}.o'; b = f'{BASE}/asm/{self.name}.bin'
        subprocess.run(args + ['-o', o, f'{BASE}/asm/conv_t.s'], check=True)
        subprocess.run(['m68k-linux-gnu-objcopy', '-O', 'binary', '-j', '.text', o, b], check=True)
        code = open(b, 'rb').read()
        assert self.unpatched[addr:addr + 0x400] == pad * 0x400, 'converter area is not layout padding'
        self.put(addr, code, 'converter')
        assert self.img[hook:hook + 6] == bytes.fromhex('4ef8') + struct.pack('>H', copyfn) + bytes.fromhex('4e71'), 'hook'
        self.put(hook, bytes.fromhex('4ef9') + L(cpu_addr(addr)), 'hook')

    # ------------------------------------------------------------- output
    def save_image(self):
        os.makedirs(f'{OUT}/{self.name}', exist_ok=True)
        open(f'{OUT}/{self.name}/main.bin', 'wb').write(self.img)

    def mra(self, title, setname, zips, okifiles, sprfiles, dips, rotate_vertical=True, comment='', year='1994',
            manufacturer='Comad'):
        parts = []
        def emit(dst, s, n):
            while n:
                bank = [b for b in self.banks if b[0] <= s < b[0] + (0x100000 if b[1] == 'il' else len(rd(b[2])))][0]
                base, kind, f = bank
                if kind == 'il' and s - base >= 2 * len(rd(f[0])):      # past the end of a short ROM pair: padding
                    chunk = min(n, base + 0x100000 - s)
                    assert set(self.src[s:s + chunk]) <= {0xff}
                    parts.append(f'        <part repeat="0x{chunk:x}"> FF</part>'); s += chunk; n -= chunk; continue
                if kind == 'il':
                    chunk = min(n, base + 2 * len(rd(f[0])) - s); off = (s - base) // 2; ln = chunk // 2
                    ev, od = f
                    parts.append('        <interleave output="16">\n'
                        f'            <part name="{os.path.basename(od)}" crc="{crc(od)}" offset="0x{off:x}" length="0x{ln:x}" map="01"/>\n'
                        f'            <part name="{os.path.basename(ev)}" crc="{crc(ev)}" offset="0x{off:x}" length="0x{ln:x}" map="10"/>\n'
                        '        </interleave>')
                else:
                    chunk = min(n, base + len(rd(f)) - s)
                    parts.append(f'        <part name="{os.path.basename(f)}" crc="{crc(f)}" offset="0x{s - base:x}" length="0x{chunk:x}"/>')
                s += chunk; n -= chunk
        for dst, s, n in self.layout:
            if s is None: parts.append(f'        <part repeat="0x{n:x}"> FF</part>')
            else: emit(dst, s, n)
        def sw(b):
            b = bytearray(b); b[0::2], b[1::2] = b[1::2], b[0::2]; return bytes(b)
        lu, lp = sw(self.unpatched), sw(self.img)
        runs = []
        for i in sorted(self.patches):
            if lu[i] == lp[i] and lu[i ^ 1] == lp[i ^ 1]: continue
            i &= ~1
            if runs and i - runs[-1][1] <= 8: runs[-1][1] = i + 2
            else: runs.append([i, i + 2])
        px = ['        <patch offset="0x%x">%s</patch>' % (a + 4, ' '.join('%02X' % x for x in lp[a:b])) for a, b in runs]
        oki = b''.join(rd(f) for f in okifiles); spr = b''.join(rd(f) for f in sprfiles)
        assert len(oki) <= 0x100000 and len(spr) <= 0x100000
        okp = [f'        <part name="{os.path.basename(f)}" crc="{crc(f)}"/>' for f in okifiles]
        if len(oki) < 0x100000: okp.append(f'        <part repeat="0x{0x100000 - len(oki):x}"> 00</part>')
        spp = [f'        <part name="{os.path.basename(f)}" crc="{crc(f)}"/>' for f in sprfiles]
        if len(spr) < 0x100000: spp.append(f'        <part repeat="0x{0x100000 - len(spr):x}"> 00</part>')
        rot = '<rotation>vertical (cw)</rotation>' if rotate_vertical else '<rotation>horizontal</rotation>'
        core_mod = '01 80' if rotate_vertical else '00 80'
        dipx = '\n'.join('        ' + x for x in dips)
        if COMAD:
            hdr = f'''<!-- {title} on jtcomad, a personal fork of Jotego's jtgals core (5 MB CPU ROM
     plus a 1 MB extension ROM at 0xB00000, OKI at 0xA80001, palette-based fg transparency). The ROM is assembled from your own MAME zip(s) and patched (work RAM relocated,
     VU-002 sprites converted to Pandora format each frame{comment}). Requires jtcomad.rbf. -->'''
        else:
            hdr = f'''<!-- {title} running on Jotego's jtgals (Gals Panic) core.
     UNOFFICIAL port: the ROM is assembled from your own MAME zip(s) and patched so the Comad game runs on the
     original Gals Panic hardware the core implements (work RAM relocated, VU-002 sprites converted to Pandora
     format each frame, OKI M6295 moved to 0x400001{comment}).
     Requires jtgals.rbf and jtbeta.zip (Jotego beta). Port tested with jtfriday_261012. -->'''
        tag = 'Comad core' if COMAD else 'jtgals port'
        beta = '' if COMAD else '''
    <rom index="17" zip="jtbeta.zip" md5="None">
        <part name="beta.bin" crc="8b6976d8"/>
    </rom>'''
        body = f'''{hdr}
<misterromdescription>
    <name>{title} ({tag})</name>
    <setname>{setname}</setname>
    {rot}
    <mameversion>0282</mameversion>
    <year>{year}</year>
    <manufacturer>{manufacturer}</manufacturer>
    <players>2</players>
    <rbf>{CORE}</rbf>
    <joystick>4</joystick>
    <region>World</region>
    <rom index="0" zip="{'|'.join(zips)}" md5="None">
        <part> 00 00 00 00 </part>
{chr(10).join(parts)}
{chr(10).join(okp)}
{chr(10).join(spp)}
{chr(10).join(px)}
    </rom>{beta}
    <rom index="1">
        <part>{core_mod}</part>
    </rom>
    <switches page_id="1" page_name="Switches" base="16" default="ff,ff">
{dipx}
    </switches>
    <buttons names="Cut,Unused,Start,Coin,Core credits" default="A,B,Start,Select,-" count="2"/>
</misterromdescription>
'''
        fn = f'{OUT}/{self.name}/{title} ({tag}).mra'
        open(fn, 'w').write(body)
        full = b'\0\0\0\0' + lp + oki + b'\0' * (0x100000 - len(oki)) + spr + b'\0' * (0x100000 - len(spr))
        open(f'{OUT}/{self.name}/expected.md5', 'w').write(hashlib.md5(full).hexdigest())
        if COMAD: open(f'{OUT}/{self.name}/rom.bin', 'wb').write(full)          # for jtsim
        open(f'{OUT}/{self.name}/oki.bin', 'wb').write(oki + b'\0' * (0x100000 - len(oki)))
        open(f'{OUT}/{self.name}/spr.bin', 'wb').write(spr + b'\xff' * (0x100000 - len(spr)))
        self.log.append('patch blocks %d, bytes %d' % (len(runs), sum(b - a for a, b in runs)))
        print('\n'.join(self.log)); print('MRA:', fn)
        return fn

_DSW1 = [
    '<dip name="Difficulty" bits="0,1" ids="Hardest,Hard,Easy,Normal"/>',
    '<dip name="Lives" bits="4,5" ids="5,2,4,3"/>',
    '<dip name="Demo Sounds" bits="6" ids="Off,On"/>',
]
# fantasia, fantasiaa, fantasiab, fantasian (MAME "fantasia" inputs)
DIPS_FANTASIA = _DSW1 + [
    '<dip name="Flip Screen" bits="9" ids="On,Off"/>',
    '<dip name="Service Mode" bits="10" ids="On,Off"/>',
    '<dip name="Coin A" bits="11,12,13" ids="1C/4C,1C/6C,1C/3C,1C/2C,1C/4C,2C/1C,1C/1C,1C/1C"/>',
    '<dip name="Coin B" bits="14,15" ids="1C/6C,1C/2C,2C/1C,1C/1C"/>',
]
# New Fantasia, Hot Night, Fantasy '95 (with service switch)
_COIN_MODE = [
    '<dip name="Coin Mode" bits="11" ids="Mode 2,Mode 1"/>',
    '<dip name="Coin A (Mode 1 / Mode 2)" bits="12,13" ids="1C/4C | 1C/6C,1C/2C | 1C/3C,2C/1C,1C/1C"/>',
    '<dip name="Coin B (Mode 1 / Mode 2)" bits="14,15" ids="1C/4C | 1C/6C,1C/2C | 1C/3C,2C/1C,1C/1C"/>',
]
DIPS_NEWFANT = _DSW1 + ['<dip name="Service Mode" bits="10" ids="On,Off"/>'] + _COIN_MODE
# Miss World '96, Super Miss World, Fantasia II, WOW New Fantasia, Miss World 2002
DIPS_MW = _DSW1 + _COIN_MODE
