#!/usr/bin/env python3
"""Comad boards with LZ pictures and 5 MB of CPU ROM (Fantasia II, WOW New Fantasia, Miss World 2002).
   Same treatment as games_c0 (Miss World '96) for code, plus a girl subset so the data fits the 4 MB ROM space:
   masks (raw 0x9540 each, table of (ptr, meta)) and compressed pictures (offset table) of the kept girls are packed
   into the original mask area and the space after the picture table; dropped girls point at kept ones."""
import os, sys, struct, subprocess
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from port import *
from games_c0 import asm, one, flip_patch, SHADOW_C0, FLAGS_C0, MARK_C0
from lzenc import tokens_orig

MASKLEN = 0x9540

def ram_map(rb):
    def m(v):
        for lo, hi, dst in ((0x0f00, 0x2f00, 0x51c000), (0x0000, 0x0900, 0x51e000), (0x5000, 0x5900, 0x51e900),
                            (0x5f00, 0x6000, 0x51f200), (0x7000, 0x7100, 0x51f300), (0x7600, 0x7800, 0x51f600)):
            if rb + lo <= v < rb + hi: return dst + v - rb - lo
    return m
spr_map = lambda v: SHADOW_C0 + (v - 0x700000) if 0x700000 <= v < 0x701000 else None

def girl_plan(p, pictab, masktab, n, keep):
    """returns layout list and remap info. keep = list of kept girl indices"""
    src = bytes(p.src) + bytes(64)
    L = lambda a: struct.unpack('>I', src[a:a + 4])[0]
    pics = []
    for i in range(n):
        off = L(pictab + 4 * i); toks, cl = tokens_orig(src, pictab, i)
        pics.append((pictab + off, 8 + cl + 2))          # +2: decoder may prefetch one word past the end
    masks = [L(masktab + 8 * i) for i in range(n)]
    data_masks = [m for m in masks if m >= 0x100000]
    mlo, mhi = min(data_masks), max(data_masks) + MASKLEN
    assert mlo == 0x100000
    pend = max(a + l for a, l in pics)
    holes = [[mlo, mhi], [(pictab + 4 * n + 0xf) & ~0xf, 0x400000]]
    items = []                                           # (kind, girl, src, len)
    for j in keep:
        if masks[j] >= 0x100000: items.append(('m', j, masks[j], MASKLEN))
        items.append(('p', j) + pics[j])
    place = {}
    for it in sorted(items, key=lambda x: -x[3]):
        for h in holes:
            if h[1] - h[0] >= it[3]:
                place[it[:2]] = h[0]; h[0] = (h[0] + it[3] + 1) & ~1; break
        else:
            return None
    # layout: prog + other data identity, holes filled
    lay = []; pos = 0
    regions = [(0, mlo, 'id'), (mlo, mhi, 'A'), (mhi, holes[1][0] if False else (pictab + 4 * n + 0xf) & ~0xf, 'id'),
               ((pictab + 4 * n + 0xf) & ~0xf, 0x400000, 'B')]
    for lo, hi, kind in regions:
        if kind == 'id':
            lay.append((lo, lo, hi - lo)); continue
        its = sorted([(place[it[:2]], it) for it in items if lo <= place[it[:2]] < hi])
        q = lo
        for dst, it in its:
            if dst > q: lay.append((q, None, dst - q))
            lay.append((dst, it[2], it[3])); q = dst + it[3]
        if q < hi: lay.append((q, None, hi - q))
    return lay, place, masks, pics

def build(name, setname, title, banks, spr, oki, refs, zips, keep, girls_label, rb=0xf80000, timers=(0x800008, 0x80000a, 0x80000c, 0x80000e),
          year='1997', manufacturer='Comad', dips=DIPS_MW, yoff=15, vertical=False, skip=()):
    p = Port(name, banks, 0x500000)
    src = bytes(p.src)
    decs = [i for i in range(0, 0x100000, 2) if src.startswith(bytes.fromhex('48e7fffe08b90000'), i)
            and src[i + 12:i + 18] == bytes.fromhex('43f900520000')]
    assert decs, 'decompressor'
    flag = struct.unpack('>I', src[decs[0] + 8:decs[0] + 12])[0]
    # picture / mask tables from the decompressor call sites and the mask loader
    calls = [i for i in range(0, 0x100000, 2) if src[i:i + 2] == b'\x4e\xb9' and struct.unpack('>I', src[i + 2:i + 6])[0] in decs]
    tabs = sorted(set(struct.unpack('>I', src[c - 10:c - 6])[0] for c in calls if src[c - 12:c - 10] == b'\x22\x3c'))
    big = [t for t in tabs if struct.unpack('>I', src[t:t + 4])[0] // 4 > 20]
    assert len(big) == 1, [hex(t) for t in tabs]
    pictab = big[0]; n = struct.unpack('>I', src[pictab:pictab + 4])[0] // 4
    import re
    m_ = re.search(rb'\x4d\xf9(....)\x42\x46\x1c\x39' + struct.pack('>I', rb + 0x7005) + rb'\xe7\x46', src[:0x100000], re.S)
    masktab = struct.unpack('>I', m_.group(1))[0]
    plan = girl_plan(p, pictab, masktab, n, keep)
    assert plan, 'girl subset does not fit'
    lay, place, masks, pics = plan
    p.set_layout(lay)
    p.log.append('girls kept %s (%d of %d), pictab %06x masktab %06x' % (girls_label, len(keep), n, pictab, masktab))
    # --- girl table remaps
    kept = sorted(keep)
    def target(j):
        if j in keep: return j
        return kept[j % len(kept)] if j < kept[0] else kept[(j - kept[0]) % len(kept)]
    for j in range(n):
        t = target(j)
        newm = place[('m', t)] if masks[t] >= 0x100000 else masks[t]
        p.put(masktab + 8 * j, L(newm) + bytes(p.unpatched[masktab + 8 * t + 4:masktab + 8 * t + 8]), 'mask')
        p.put(pictab + 4 * j, L((place[('p', t)] - pictab) & 0xffffffff), 'pic')
    # --- code (same as games_c0, RAM base rb)
    rm = ram_map(rb)
    sv = [h - 6 for h in p.find(bytes.fromhex('41f90058000043f9') + L(rb + 0x3000))]
    boot = one(p, '227c' + '%08x' % rb + '203c00003fff4299', 'boot clear')
    fgc = one(p, '227c00500001203c00003fff', 'fg clear')
    dead = set()
    for d0 in decs: dead |= set(range(d0, d0 + 0x2b4))
    for s in sv: dead |= set(range(s, s + 0x40))
    dead |= set(range(boot, boot + 0x12))
    p.relocate(refs, rm, 'RAM', skip=set(skip) | dead)
    p.relocate(refs, spr_map, 'SPR', skip=dead)
    oh = one(p, 'e84e0246000f1e39', 'okiwait')
    okiaddr = p.getl(oh + 8)
    p.relocate(refs, lambda v: OKIA, 'OKI', coords=False)
    p.put(0, L(rm(p.getl(0))), 'ssp')
    for s in sv: p.put(s, bytes.fromhex('4e75'), 'view2 save/restore off')
    p.put(fgc + 8, L(0x37ff), 'fg clear visible rows only')
    h = p.find(bytes.fromhex('e84e0246000f1e39') + L(OKIA)); assert len(h) == 1, (h, hex(okiaddr))
    p.put(h[0] + 6, bytes.fromhex('7eff4e714e71'), 'okiwait', force=True)
    for t in timers:
        for hh in p.find(L(t)):
            op = p.getw(hh - 2)
            if (op & 0xf1ff) == 0x1039:
                p.put(hh - 2, struct.pack('>H', 0x70ff | ((op >> 9) & 7) << 9) + bytes.fromhex('4e714e71'), 'timer')
                p.log.append('timer read %06x (%06x) patched' % (hh - 2, t))
    # --- new code in the zero padding after the decompressor
    pad = max(decs) + 0x300
    while p.unpatched[pad:pad + 16] != bytes(16): pad += 16
    pad += 16
    code, sym = asm(name + '_dec', 'mw_decomp.s', dict(FLAGVAR=rm(flag), BOOTRET=boot + 0x12))
    assert p.unpatched[pad:pad + 0x800] == bytes(0x800), hex(pad)
    p.put(pad, code, 'decompressor')
    for d0 in decs: p.put(d0, bytes.fromhex('4ef9') + L(pad + sym['decomp']), 'decomp hook')
    p.put(boot, bytes.fromhex('4ef9') + L(pad + sym['bootclr']), 'boot clear hook')
    p.log.append('decompressors %s -> %06x, flag %06x, oki %06x' % ([hex(x) for x in decs], pad, flag, okiaddr))
    if not vertical: flip_patch(p, pad, sym)
    # face portraits (select screen / side panel) follow the same girl substitution as the pictures
    from facefind import face_tables
    ftabs = face_tables(bytes(p.unpatched[:0x100000]), rb)
    assert ftabs, 'no face tables'
    for ftab in ftabs:
        ents = [struct.unpack('>I', p.unpatched[ftab + 4 * k:ftab + 4 * k + 4])[0] for k in range(n)]
        assert all(e < 0x500000 for e in ents), hex(ftab)
        nf = 0
        for j in range(n):
            t = target(j)
            if t != j: p.put(ftab + 4 * j, L(ents[t]), 'face'); nf += 1
        p.log.append('face table %06x: %d entries remapped' % (ftab, nf))
    a = one(p, '23c000780010', 'ofs')
    assert p.getw(a - 12) == 0x2039 and p.getw(a - 6) == 0xd0b9, 'ofs pattern'
    ofs1, ofs2 = p.getl(a - 10), p.getl(a - 4)
    hook = one(p, '4ef801004e71', 'hook')
    v4 = p.getl(0x70)
    assert p.img[v4:v4 + 6] == bytes.fromhex('027cf8ff4eb9') and p.getw(v4 + 10) == 0x4e73, 'irq4 handler'
    irq4fn = p.getl(v4 + 6)
    conv_addr = (pad + len(code) + 0x1f) & ~0xf
    p.converter(hook, 0x100, ofs1, ofs2, addr=conv_addr, irq4fn=irq4fn, yoff=yoff, pad=b'\0',
                bufs=dict(SHADOW=SHADOW_C0, FLAGS=FLAGS_C0, MARK=MARK_C0))
    p.save_image()
    return p.mra('%s (girls %s)' % (title, girls_label), setname, list(zips), oki, spr, dips, rotate_vertical=vertical,
                 year=year, manufacturer=manufacturer,
                 comment=';\n     picture decompressor rewritten to use the bitmap as its window;\n     the full game is 5 MB, the core maps 4 MB: '
                         'this MRA holds girls %s, the other girls repeat these' % girls_label)
