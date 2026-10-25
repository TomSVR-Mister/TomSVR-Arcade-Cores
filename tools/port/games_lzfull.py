import os
#!/usr/bin/env python3
"""WOW New Fantasia / Miss World 2002 with ALL girls in one MRA.
The data ROMs hold, besides the pictures, masks and face portraits, about 1.2 MB the game never reads (leftovers,
verified by coverage runs over 40 consecutive stages + attract / select / continue).  Only the used data is
copied: masks, face sets (48x56 and 40x48) and the picture block (table + compressed pictures, kept together so
the table's relative offsets stay valid).  Code changes are the same as games_lz (RAM relocation, decompressor using
the bitmap as window, flip, sprite converter) plus the Monster picture DIP (DSW1 bits 2,7)."""
import sys, struct, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from port import *
from games_c0 import asm, one, flip_patch, SHADOW_C0, FLAGS_C0, MARK_C0
from games_lz import ram_map, spr_map, MASKLEN
from lzenc import tokens_orig
from facefind import face_tables

def build(name, setname, title, banks, spr, oki, refs, zips, rb=0xf80000, timers=(0x800008, 0x80000a, 0x80000c, 0x80000e),
          year='2002', manufacturer='Comad', dips=DIPS_MW, yoff=15, progfree=(), derive40=False):
    p = Port(name, banks, 0x500000)
    src = bytes(p.src) + bytes(64)
    Lg = lambda a: struct.unpack('>I', src[a:a + 4])[0]
    decs = [i for i in range(0, 0x100000, 2) if src.startswith(bytes.fromhex('48e7fffe08b90000'), i)
            and src[i + 12:i + 18] == bytes.fromhex('43f900520000')]
    flag = Lg(decs[0] + 8)
    calls = [i for i in range(0, 0x100000, 2) if src[i:i + 2] == b'\x4e\xb9' and Lg(i + 2) in decs]
    tabs = sorted(set(Lg(c - 10) for c in calls if src[c - 12:c - 10] == b'\x22\x3c'))
    pictab = [t for t in tabs if Lg(t) // 4 > 20][0]; n = Lg(pictab) // 4
    m_ = re.search(rb'\x4d\xf9(....)\x42\x46\x1c\x39' + struct.pack('>I', rb + 0x7005) + rb'\xe7\x46', src[:0x100000], re.S)
    masktab = struct.unpack('>I', m_.group(1))[0]
    masks = [Lg(masktab + 8 * j) for j in range(n)]
    pics = [((pictab + Lg(pictab + 4 * j)) & 0xffffffff, 8 + tokens_orig(src, pictab, j)[1] + 2) for j in range(n)]
    pend = (max(a + l for a, l in pics) + 1) & ~1
    assert min(a for a, l in pics) > pictab
    if COMAD:                                                       # jtcomad: the whole 5 MB game at its original addresses
        assert not derive40
        p.identity_layout()
        p.log.append('all %d girls + monster stage at their original addresses (5 MB core)' % n)
    else:                                                           # find, pack and re-point the data that is used
        ftabs = face_tables(src[:0x100000], rb)
        fsets = []
        for t, (entry, _, _) in ftabs.items():
            rows, cols = struct.unpack('>H', src[entry + 14:entry + 16])[0] + 1, struct.unpack('>H', src[entry + 20:entry + 22])[0] + 1
            ents = [Lg(t + 4 * k) for k in range(n)]
            assert all(0x100000 <= e < 0x500000 for e in ents), hex(t)
            fsets.append((t, rows * cols * 2, ents))
        # ------------------------------------------------------------------ monster stage data (raw pictures, masks, faces)
        MONPIC = 192 * 199 * 2
        mt_ = [Lg(m.start() + 2) for m in re.finditer(rb'\x49\xf9(....)\x30\x39' + struct.pack('>I', rb + 0x268c), src[:0x100000], re.S)]
        assert len(mt_) == 2, mt_
        monmasktab, monpictab = mt_
        monmasks = [Lg(monmasktab + 8 * k) for k in range(2)]
        monpics = [Lg(monpictab + 4 * k) for k in range(2)]
        f56 = [f for f in fsets if f[1] == 48 * 56 * 2][0]
        monfacetab = f56[0] + 4 * n
        monfaces = [Lg(monfacetab + 4 * k) for k in range(2)]
        assert all(0x100000 <= v < 0x500000 for v in monpics + monfaces), [hex(v) for v in monpics + monfaces]
        # ------------------------------------------------------------------ items and packing
        items = [('pics', pictab, pend - pictab)]                       # (key, source, size); the picture block first
        items += [(('mask', m), m, MASKLEN) for m in sorted(set(m for m in masks + monmasks if m >= 0x100000))]
        items += [(('mpic', v), v, MONPIC) for v in monpics]
        for t, size, ents in fsets:
            if derive40 and size == 40 * 48 * 2: continue
            items += [(('face', e), e, size) for e in sorted(set(ents))]
        items += [(('face', e), e, 48 * 56 * 2) for e in monfaces if ('face', e) not in [i[0] for i in items]]
        regions = [[0x100000, 0x400000]] + [list(r) for r in progfree]
        place = {}
        first = True
        for key, a, size in ([items[0]] + sorted(items[1:], key=lambda x: -x[2])):
            for r in regions:
                if r[1] - r[0] >= size: place[key] = r[0]; r[0] = (r[0] + size + 1) & ~1; break
            else: raise AssertionError('does not fit: %s %d' % (str(key), size))
        used = sum(i[2] for i in items)
        p.log.append('all %d girls + monster stage: %d KB placed; free left %s' % (n, used // 1024, [(hex(a), (b - a) // 1024) for a, b in regions]))
        segs = [(0, 0, 0x100000)]
        for lo, hi in progfree:                                         # cut the reused program-ROM ranges out of the identity copy
            nxt = []
            for d0, s0, n0 in segs:
                if d0 + n0 <= lo or d0 >= hi: nxt.append((d0, s0, n0)); continue
                if d0 < lo: nxt.append((d0, s0, lo - d0))
                if d0 + n0 > hi: nxt.append((hi, s0 + hi - d0, d0 + n0 - hi))
            segs = nxt
        segs += [(place[k], a, size) for k, a, size in items]
        segs.sort(); lay = []; q = 0
        for d0, s0, n0 in segs:
            assert d0 >= q, (hex(d0), hex(q))
            if d0 > q: lay.append((q, None, d0 - q))
            lay.append((d0, s0, n0)); q = d0 + n0
        if q < 0x400000: lay.append((q, None, 0x400000 - q))
        p.set_layout(lay)
        newtab = place['pics']
        # ------------------------------------------------------------------ data pointers
        for j, m in enumerate(masks):
            if m >= 0x100000: p.put(masktab + 8 * j, L(place[('mask', m)]), 'mask')
        for k, m in enumerate(monmasks):
            if m >= 0x100000: p.put(monmasktab + 8 * k, L(place[('mask', m)]), 'monster mask')
        for k, v in enumerate(monpics): p.put(monpictab + 4 * k, L(place[('mpic', v)]), 'monster picture')
        for k, v in enumerate(monfaces): p.put(monfacetab + 4 * k, L(place[('face', v)]), 'monster face')
        for t, size, ents in fsets:
            if derive40 and size == 40 * 48 * 2: continue
            for k, e in enumerate(ents): p.put(t + 4 * k, L(place[('face', e)]), 'face')
        hits = [a for a in range(0, 0x100000, 2) if Lg(a) == pictab]
        assert 1 <= len(hits) <= 6, hits
        for a in hits: p.put(a, L(newtab), 'picture table')
        p.log.append('picture table %06x -> %06x, monster tables %06x %06x faces %06x' % (pictab, newtab, monmasktab, monpictab, monfacetab))
        if derive40:
            e40 = [e for t, (e, _, _) in ftabs.items() if struct.unpack('>H', src[e + 20:e + 22])[0] + 1 == 40][0]
            p.log.append('40x48 portraits drawn by scaling the 48x56 ones (routine %06x)' % e40)
    # ------------------------------------------------------------------ code (same as games_lz)
    rm = ram_map(rb)
    sv = [h - 6 for h in p.find(bytes.fromhex('41f90058000043f9') + L(rb + 0x3000))]
    boot = one(p, '227c' + '%08x' % rb + '203c00003fff4299', 'boot clear')
    fgc = one(p, '227c00500001203c00003fff', 'fg clear')
    dead = set()
    for d0 in decs: dead |= set(range(d0, d0 + 0x2b4))
    for s in sv: dead |= set(range(s, s + 0x40))
    dead |= set(range(boot, boot + 0x12))
    p.relocate(refs, rm, 'RAM', skip=dead)
    p.relocate(refs, spr_map, 'SPR', skip=dead)
    p.relocate(refs, lambda v: OKIA, 'OKI', coords=False)
    p.put(0, L(rm(p.getl(0))), 'ssp')
    for s in sv: p.put(s, bytes.fromhex('4e75'), 'view2 save/restore off')
    p.put(fgc + 8, L(0x37ff), 'fg clear visible rows only')
    h = p.find(bytes.fromhex('e84e0246000f1e39') + L(OKIA)); assert len(h) == 1
    p.put(h[0] + 6, bytes.fromhex('7eff4e714e71'), 'okiwait', force=True)
    for t in timers:
        for hh in p.find(L(t)):
            op = p.getw(hh - 2)
            if (op & 0xf1ff) == 0x1039:
                p.put(hh - 2, struct.pack('>H', 0x70ff | ((op >> 9) & 7) << 9) + bytes.fromhex('4e714e71'), 'timer')
    # new code in the padding after the original decompressor
    pad = max(decs) + 0x300
    while p.unpatched[pad:pad + 16] != bytes(16): pad += 16
    pad += 16
    code, sym = asm(name + '_dec', 'mw_decomp.s', dict(FLAGVAR=rm(flag), BOOTRET=boot + 0x12))
    NOMON = os.environ.get('MONSTER') == '0'      # distributed builds: game logic as the original (no Monster picture DIP)
    mon, msym = asm(name + '_mon', 'monster.s', dict(DSW=rm(rb + 0xb), THR=rm(rb + 0x2626)))
    assert p.unpatched[pad:pad + 0x1000] == bytes(0x1000), hex(pad)
    p.put(pad, code, 'decompressor')
    for d0 in decs: p.put(d0, bytes.fromhex('4ef9') + L(pad + sym['decomp']), 'decomp hook')
    p.put(boot, bytes.fromhex('4ef9') + L(pad + sym['bootclr']), 'boot clear hook')
    flip_patch(p, pad, sym)
    monaddr = (pad + len(code) + 0xf) & ~0xf
    if not NOMON: p.put(monaddr, mon, 'monster DIP')
    endcode = monaddr + len(mon)          # same layout either way (the converter stays where it was tested)
    if derive40:
        fs, fsym = asm(name + '_f40', 'facescale.s', dict(TAB56=f56[0]))
        faddr = (endcode + 0xf) & ~0xf
        p.put(faddr, fs, 'face scaler'); endcode = faddr + len(fs)
        assert p.unpatched[e40:e40 + 6] == bytes.fromhex('43fa') + p.unpatched[e40 + 2:e40 + 4] + bytes.fromhex('4e71'), hex(e40)
        p.put(e40, bytes.fromhex('4ef9') + L(faddr + fsym['face40']), 'face scaler hook')
    if not NOMON:
        pat = bytes.fromhex('33fc0006') + L(rb + 0x2626)
        thr = [a for a in range(0, 0x100000, 2) if p.unpatched[a:a + 8] == pat]; assert len(thr) == 1, thr
        p.put(thr[0], bytes.fromhex('4eb9') + L(monaddr + msym['moninit']) + bytes.fromhex('4e71'), 'monster DIP', force=True)
        dr = [a for a in range(0x1000, 0x3000, 2) if p.unpatched[a:a + 8] == bytes.fromhex('3d7cfffd00226000')]; assert len(dr) == 1, dr
        p.put(dr[0], bytes.fromhex('4eb9') + L(monaddr + msym['mondrain']), 'monster pace DIP')
    # sprite converter
    a = one(p, '23c000780010', 'ofs')
    ofs1, ofs2 = p.getl(a - 10), p.getl(a - 4)
    hook = one(p, '4ef801004e71', 'hook')
    v4 = p.getl(0x70); assert p.img[v4:v4 + 6] == bytes.fromhex('027cf8ff4eb9')
    conv_addr = (endcode + 0x1f) & ~0xf
    p.converter(hook, 0x100, ofs1, ofs2, addr=conv_addr, irq4fn=p.getl(v4 + 6), yoff=yoff, pad=b'\0',
                bufs=dict(SHADOW=SHADOW_C0, FLAGS=FLAGS_C0, MARK=MARK_C0))
    p.save_image()
    dips = list(dips) + ([] if NOMON else ['<dip name="Monster picture" bits="2,7" ids="Off (slow meter),Off,Slow,Normal"/>'])
    return p.mra(title, setname, list(zips), oki, spr, dips, rotate_vertical=False, year=year, manufacturer=manufacturer,
                 comment=';\n     picture decompressor rewritten to use the bitmap as its window;\n     all %d girls' % n + ('' if COMAD else
                         ': data the game never reads is left out so everything fits the 4 MB the core maps'))
