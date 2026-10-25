#!/usr/bin/env python3
"""Fantasia family (fantasia, fantasiab, fantasiaa, fantasian): same data ROMs, different program."""
import sys, struct
sys.path.insert(0, '/tmp/claude-0/-home-claude/e1042311-2b93-5281-bddb-91ed22183aec/scratchpad/work')
from port import *

DATA = [(0x100000, 'il', ('fantasia/9.fg_ind87', 'fantasia/5.fg_ind83')),
        (0x200000, 'il', ('fantasia/8.fg_ind86', 'fantasia/4.fg_ind82')),
        (0x300000, 'il', ('fantasia/7.fg_ind85', 'fantasia/3.fg_ind81')),
        (0x400000, 'il', ('fantasia/10.imag2', 'fantasia/6.imag1'))]
FACES, TITLE = (0x4c3ec0, 0x2ac00), (0x4a7ec0, 0x1c000)
X, XLEN = [0x4829c0, 0x48bf00, 0x495440, 0x49e980], 0x9540
A0, B0 = 0x1d68c0, 0x3d9d42
newF = A0; newT = newF + FACES[1]; newX = [newT + TITLE[1], B0, B0 + XLEN, B0 + 2 * XLEN]

GIRL0, GLEN = 0x22a800, 0x12c0e
girl = lambda j: GIRL0 + j * GLEN
mask = lambda j: 0x100000 + j * XLEN
NG, DROP = 32, 9                                      # 32 girls, 9 do not fit

def holes_for(part):
    if part == 'A':                                   # keep girls 0-22: masks 23-31 area + space after girl 22
        return [(A0, 0x22a800), (B0, 0x400000)]
    # keep girls 9-31: masks 0-8 area, girls 0-8 area, space after girl 23 (girls 24-31 are moved)
    return [(0x100000, mask(DROP)), (girl(0), girl(DROP)), (girl(24), 0x400000)]

def keep_set(part): return list(range(NG - DROP)) if part == 'A' else list(range(DROP, NG))
def target(j, part):
    if part == 'A': return j - (NG - DROP) if j >= NG - DROP else j
    return j + (NG - DROP) if j < DROP else j

def plan(items, holes):
    """first-fit-decreasing placement of (src,len) items into holes -> {src: dst}"""
    free = [list(h) for h in holes]; place = {}
    for src, n in sorted(items, key=lambda x: -x[1]):
        for h in free:
            if h[1] - h[0] >= n: place[src] = h[0]; h[0] += n; break
        else: raise SystemExit('does not fit: %x' % src)
    return place

def pictures(p, items, part='A'):
    if part == 'B': items = list(items) + [(girl(j), GLEN) for j in range(24, NG)]
    holes = holes_for(part)
    place = plan(items, holes)
    lay = []; pos = 0
    for h0, h1 in holes:
        if pos < h0: lay.append((pos, pos, h0 - pos))
        q = h0
        for src, n in sorted(items, key=lambda x: place[x[0]]):
            if h0 <= place[src] < h1:
                lay.append((place[src], src, n)); q = place[src] + n
        if q < h1: lay.append((q, None, h1 - q))
        pos = h1
    if pos < 0x400000: lay.append((pos, pos, 0x400000 - pos))
    p.set_layout(lay)
    return place

ITEMS_ALL = []
def picture_tables(p, place, faces, part='A'):
    moved_girls = {girl(j) for j in range(NG)}
    for old, new in place.items():
        if old == faces[0] or old in moved_girls: continue
        hits = [h for h in p.find(L(old)) if h % 2 == 0]
        assert hits, hex(old)
        for h in hits: p.put(h, L(new), 'pic')
        p.log.append('pic %06x -> %06x at %s' % (old, new, [hex(h) for h in hits]))
    og = lambda a: struct.unpack('>I', p.unpatched[a:a + 4])[0]
    GI = {girl(j): j for j in range(NG)}; MI = {mask(j): j for j in range(NG)}
    newgirl = lambda t: place.get(girl(t), girl(t))
    ng = nm = 0
    for a in range(4, 0x100000 - 16, 2):
        v = og(a)
        if v in GI and (og(a - 4) in GI or og(a + 4) in GI):
            t = target(GI[v], part)
            if newgirl(t) != v: p.put(a, L(newgirl(t)), 'girls'); ng += 1
        if v in MI:
            j = MI[v]; t = target(j, part)
            if t == j: continue
            if og(a - 8) in MI or og(a + 8) in MI:            # (mask, meta) pairs
                src = a + 8 * (t - j)
                assert og(src) == mask(t), hex(a)
                p.put(a, bytes(p.unpatched[src:src + 8]), 'masks'); nm += 1
            elif og(a - 4) in MI or og(a + 4) in MI:
                p.put(a, L(mask(t)), 'masks'); nm += 1
    p.log.append('girl entries remapped %d, mask entries remapped %d' % (ng, nm))
    for a in range(4, 0x100000 - 16, 2):          # nothing may still point past 4 MB
        v = p.getl(a)
        if GIRL0 <= v < GIRL0 + NG * GLEN and (v - GIRL0) % GLEN == 0: assert v + GLEN <= 0x400000, hex(a)
        if v in MI and (p.getl(a - 8) in MI or p.getl(a + 8) in MI or p.getl(a - 4) in MI or p.getl(a + 4) in MI): assert MI[v] in keep_set(part), hex(a)
    nf = 0
    newF = place[faces[0]]
    isface = lambda v: faces[0] <= v < faces[0] + faces[1] and (v - faces[0]) % 0x1200 == 0
    for a in range(4, 0x100000 - 12, 2):
        if isface(og(a)) and (isface(og(a + 4)) or isface(og(a - 4))):
            p.put(a, L(newF + og(a) - faces[0]), 'faces'); nf += 1
    p.log.append('faces moved %d' % nf)
    # per-girl face tables (face j = girl j) follow the girl substitution
    nr = 0
    a = 4
    while a < 0x100000 - 4 * NG:
        if all(og(a + 4 * k) == faces[0] + k * 0x1200 for k in range(NG)):
            for j in range(NG):
                t = target(j, part)
                if t != j: p.put(a + 4 * j, L(newF + t * 0x1200), 'faces', force=True); nr += 1
            a += 4 * NG
        else: a += 2
    p.log.append('face table entries remapped %d' % nr)
    # self-check: everything a table points at must read back as the original data
    nchk = 0
    for a in range(4, 0x100000 - 16, 2):
        v = og(a)
        if v in GI and (og(a - 4) in GI or og(a + 4) in GI):
            t = target(GI[v], part); w = p.getl(a)
            assert p.img[w:w + GLEN] == p.src[girl(t):girl(t) + GLEN], ('girl', hex(a)); nchk += 1
        if v in MI and (og(a - 8) in MI or og(a + 8) in MI or og(a - 4) in MI or og(a + 4) in MI):
            t = target(MI[v], part); w = p.getl(a)
            assert w == mask(t) and p.img[w:w + XLEN] == p.src[mask(t):mask(t) + XLEN], ('mask', hex(a)); nchk += 1
    for old, new in place.items():
        n = [x[1] for x in (ITEMS_ALL + [(girl(j), GLEN) for j in range(NG)]) if x[0] == old][0]
        assert p.img[new:new + n] == p.src[old:old + n], ('item', hex(old)); nchk += 1
    p.log.append('self-check ok (%d pointers)' % nchk)

def ram_map_c8(v):
    if 0xc80000 <= v < 0xc82a00: return 0x702000 + (v - 0xc80000)
    if 0xc87000 <= v < 0xc87100: return 0x53c000 + (v - 0xc87000)
    if 0xc88000 <= v < 0xc8a100: return 0x51c000 + (v - 0xc88000)
    if 0xc8f000 <= v < 0xc90000: return 0x53f000 + (v - 0xc8f000)
spr_map = lambda v: SHADOW + (v - 0x700000) if 0x700000 <= v < 0x701000 else None
oki_map = lambda v: OKIA

ITEMS_FANTASIA = [FACES, TITLE] + [(x, XLEN) for x in X]
def build(name, setname, title, prog, spr, oki, refs, skip=(), data_patch=(), timers=(0x80000a, 0x80000c), zips=('fantasia.zip',),
          data=None, items=None, faces=FACES, conv_addr=None, year='1994', manufacturer='Comad &amp; New Japan System', dips=None, part=None):
    import os
    part = part or os.environ.get('PART', 'full' if COMAD else 'A')
    if part == 'B': name += '_B'; title += ' (girls 10-32)'
    elif part == 'A': title += ' (girls 1-23)'
    p = Port(name, [(0, 'il', prog)] + (data or DATA), 0x500000)
    ITEMS_ALL[:] = list(items or ITEMS_FANTASIA)
    if part == 'full':                                  # jtcomad: the whole 5 MB game at its original addresses
        assert COMAD
        p.identity_layout(); place = None
        conv_addr = EXT
    else:
        place = pictures(p, items or ITEMS_FANTASIA, part)
    p.relocate(refs, ram_map_c8, 'RAM', skip=skip, data_patch=data_patch)
    p.relocate(refs, spr_map, 'SPR')
    p.relocate(refs, oki_map, 'OKI', coords=False)
    p.put(0, L(ram_map_c8(p.getl(0))), 'ssp')
    # boot RAM clear (movea.l #$702000,a1 ; move.l #$8000,d0) -> 0x3000 bytes
    h = p.find(L(0x702000) + bytes.fromhex('203c') + L(0x8000)); assert len(h) == 1
    p.put(h[0] + 6, L(0x17ff), 'clear')
    # OKI "wait until channel started" poll -> assume started
    oa = L(OKIA)
    h = p.find(bytes.fromhex('e84e0246000f1e39') + oa); assert len(h) == 1, h
    p.put(h[0] + 6, bytes.fromhex('7eff4e714e71'), 'okiwait', force=True)
    # Comad timer reads (0x8000xx beyond the inputs): open bus 0xffff on the core
    for t in timers:
        for hh in p.find(L(t)):
            op = p.getw(hh - 2)
            if (op & 0xf1ff) == 0x1039:               # move.b abs.l,Dn
                dn = (op >> 9) & 7
                p.put(hh - 2, struct.pack('>H', 0x70ff | dn << 9) + bytes.fromhex('4e714e71'), 'timer')
                p.log.append('timer read %06x patched' % (hh - 2))
    # sprite converter: offsets = (c80f92)+(c80fae) feeding sprite offset regs 0x780010
    h = p.find(bytes.fromhex('23c000780010')); assert len(h) == 1
    a = h[0]
    assert p.getw(a - 12) == 0x2039 and p.getw(a - 6) == 0xd0b9, 'ofs pattern'
    ofs1, ofs2 = p.getl(a - 10), p.getl(a - 4)
    hook = p.find(bytes.fromhex('4ef801004e71')); assert len(hook) == 1
    v4 = p.getl(0x70)                                   # IRQ4 vector -> andi #$f8ff,sr ; jsr fn ; rte
    assert p.img[v4:v4 + 6] == bytes.fromhex('027cf8ff4eb9') and p.getw(v4 + 10) == 0x4e73, 'irq4 handler'
    irq4fn = p.getl(v4 + 6)
    p.log.append('IRQ4 routine %06x called from converter' % irq4fn)
    if conv_addr is None:                                # put the converter in padding our own layout created
        gaps = [(d, n) for d, s, n in p.layout if s is None and n >= 0x400]
        conv_addr = (gaps[0][0] + 0xf) & ~0xf
    p.log.append('converter at %06x' % conv_addr)
    p.converter(hook[0], 0x100, ofs1, ofs2, addr=conv_addr, irq4fn=irq4fn)
    if place is not None: picture_tables(p, place, faces, part)
    p.save_image()
    return p.mra(title, setname, list(zips), oki, [spr], dips or DIPS_FANTASIA,
                 comment='' if part == 'full' else (';\n     the full game is 5 MB, the core maps 4 MB: this MRA holds girls %s, the other girls repeat these' % ('1-23' if part == 'A' else '10-32')),
                 manufacturer=manufacturer, year=year)
