#!/usr/bin/env python3
"""Extract the girl pictures from Comad / Afega EXPRO02-family MAME sets.

usage: comad_pics.py ZIPDIR OUTDIR [set ...]

Formats (found by tracing the 68k code in MAME 0.264):
  lz    Miss World '96 family, Super Model II. Nibble stream decoded by the
        routine at missw96 0x39a28: 0xxx = 15-bit literal, 10oo..o nnnn = copy
        n+1 pixels from a 16K-pixel history at o (n=0 ends), 11nn = repeat last
        pixel n+1 times. Header: 0.L, width.W, height.W. Found by scanning.
  sm    Super Model: raw little-endian words, 191x199 in rows of 193 words,
        pointer table at 0x3df22 (35 entries).
  zz    Zip & Zap: raw little-endian words, 232x196, 25 pictures from 0x100000.
  gh    Gals Hustler / Pocket Gals V.I.P.: raw big-endian words, 160x208 stored
        bottom-up, 8 pictures.
Pixel value v: colour = v>>1 as xGGGGGRRRRRBBBBB (bit 0 is a flag).
"""
import os, sys, struct, zipfile, json
import numpy as np
from PIL import Image

# set: (zip, [(even, odd) per 1 MB maincpu block, None = empty], format, args)
MW = [('mw96_09.bin', 'mw96_05.bin'), ('mw96_08.bin', 'mw96_04.bin'), ('mw96_07.bin', 'mw96_03.bin')]
SETS = {
 'missw96':  ('missw96', [('mw96_10.bin', 'mw96_06.bin')] + MW, 'lz'),
 'missw96a': ('missw96', [('missw96a/mw96n2_10.prog2', 'missw96a/mw96n2_6.prog1')] + MW, 'lz'),
 'missw96b': ('missw96', [('missw96b/mw96n3_10.prog2', 'missw96b/mw96n3_6.prog1')] + MW, 'lz'),
 'missw96c': ('missw96', [('missw96c/10_prog2.ue17', 'missw96c/6_prog1.ud17'), ('missw96c/9_im1-b.ue16b', 'missw96c/5_im1-a.ue16a'),
                          ('missw96c/8_im2-b.ue15b', 'missw96c/4_im2-a.ue15a'), ('missw96c/7_im3_b.ue14b', 'missw96c/3_im3-a.ue14a')], 'lz'),
 'missmw96': ('missw96', [('missmw96/mmw96_10.bin', 'missmw96/mmw96_06.bin'), ('missmw96/mmw96_09.bin', 'missmw96/mmw96_05.bin'),
                          ('missmw96/mmw96_08.bin', 'missmw96/mmw96_04.bin'), ('missmw96/mmw96_07.bin', 'missmw96/mmw96_03.bin')], 'lz'),
 'smissw':   ('smissw', [('10_prog2.ue17', '6_prog1.ud17'), ('9_im1-b.ue16b', '5_im1-a.ue16a'), ('8_im2-b.ue15b', '4_im2-a.ue15a'),
                         ('7_im3-b.ue14b', '3_im3-a.ue14a')], 'lz'),
 'supmodel': ('supmodel', [('prog2.12', 'prog1.7'), ('i-scr2.10', 'i-scr1.5'), ('i-scr4.9', 'i-scr3.4'), ('i-scr6.8', 'i-scr5.3'),
                           ('i-scr8.11', 'i-scr7.6')], 'sm'),
 'supmodl2': ('supmodl2', [('12_prog2.ue17', '7_prog1.ud17'), ('11_i-scr2.ue16b', '6_i-scr1.ue16a'), ('10_i-scr4.ue15b', '5_i-scr3.ue15a'),
                           ('9_i-scr6.ue14b', '4_i-scr5.ue14a'), ('8_i-scr8.ue20b', '3_i-scr7.ue20a')], 'lz'),
 'zipzap':   ('zipzap', [('ue17.bin', 'ud17.bin'), ('937.bin', '941.bin'), ('936.bin', '940.bin'), ('934.bin', '939.bin'), ('938.bin', '942.bin')], 'zz'),
 'zipzapa':  ('zipzap', [('zipzapa/31.ue17', 'zipzapa/30.ud17'), ('zipzapa/37.rd2b', 'zipzapa/33.rd2a'), ('zipzapa/38.rd3b', 'zipzapa/34.rd3a'),
                         ('zipzapa/39', 'zipzapa/35'), ('zipzapa/36.rd1b', 'zipzapa/32.rd1a')], 'zz'),
 'galhustl': ('pgalvip', [('galhustl/ue17.3', 'galhustl/ud17.4')], ('gh', 0x40000)),
 'galhustla':('pgalvip', [('galhustla/afega_3.uc17', 'galhustla/afega_4.ud17')], ('gh', 0x41000)),
 'pgalvipa': ('pgalvip', [('pgalvipa/pgalvip_3.ue17', 'pgalvipa/pgalvip_4.ud17')], ('gh', 0x40000)),
 'pgalvip':  ('pgalvip', [('afega_15.ue17', 'afega_16.ud17'), None, ('afega_13.rob1', 'afega_14.roa1')], ('gh', 0x201000)),  # pointer table says 0x200000, data really starts 0x1000 later
}

def build(zipdir, name):
    zn, blocks, _ = SETS[name]
    z = zipfile.ZipFile(os.path.join(zipdir, zn + '.zip'))
    img = bytearray(b'\xff' * (0x100000 * len(blocks)))
    for i, p in enumerate(blocks):
        if p is None: continue
        e, o = z.read(p[0]), z.read(p[1])
        img[i*0x100000:i*0x100000 + 2*len(e):2] = e
        img[i*0x100000+1:i*0x100000 + 2*len(o):2] = o
    return bytes(img)

def lz_decode(d, addr, maxpix):
    w, h = struct.unpack_from('>HH', d, addr+4)
    p = (addr + 8) * 2                        # nibble position
    nib = lambda k: (d[k >> 1] >> 4) if not k & 1 else d[k >> 1] & 15
    out, hist, hp, last = [], [0]*0x4000, 0, 0
    while len(out) < maxpix:
        t = nib(p)
        if t < 8:
            last = (t << 12 | nib(p+1) << 8 | nib(p+2) << 4 | nib(p+3)) & 0x7fff; p += 4
            out.append(last); hist[hp] = last; hp = (hp+1) & 0x3fff
        elif t < 12:
            off = (t << 12 | nib(p+1) << 8 | nib(p+2) << 4 | nib(p+3)) & 0x3fff
            n = nib(p+4)
            if n == 0: break
            p += 5
            for i in range(n+1):
                last = hist[(off+i) & 0x3fff]
                out.append(last); hist[hp] = last; hp = (hp+1) & 0x3fff
        else:
            p += 1
            for i in range((t & 3) + 1):
                out.append(last); hist[hp] = last; hp = (hp+1) & 0x3fff
    return w, h, out

def lz_scan(d, lo=0x80000):
    found = []
    for a in range(lo, len(d)-8, 2):
        if d[a:a+4] != b'\0\0\0\0': continue
        w, h = struct.unpack_from('>HH', d, a+4)
        if not (32 <= w <= 320 and 32 <= h <= 256): continue
        try: _, _, o = lz_decode(d, a, w*h+1)
        except IndexError: continue
        if len(o) == w*h: found.append((a, w, h, np.array(o, np.uint32).reshape(h, w)))
    return found

def rgb(c):
    c = c.astype(np.uint32)
    return Image.fromarray((np.stack([(c >> 5) & 31, (c >> 10) & 31, c & 31], -1) * 255 // 31).astype(np.uint8))

def pictures(d, fmt):
    """yield (kind, rom address, image); kind 'girl' or 'screen'"""
    if fmt == 'lz':
        for a, w, h, px in lz_scan(d):
            yield ('girl' if (w, h) == (191, 199) else 'screen'), a, rgb(px)
    elif fmt == 'sm':
        for i in range(35):
            a = struct.unpack_from('>L', d, 0x3df22 + 4*i)[0]
            px = np.frombuffer(d[a:a + 193*199*2], '<u2').reshape(199, 193)[:, :191] >> 1
            yield 'girl', a, rgb(px)
    elif fmt == 'zz':
        for i in range(25):
            a = 0x100000 + i*232*196*2
            yield 'girl', a, rgb(np.frombuffer(d[a:a + 232*196*2], '<u2').reshape(196, 232) >> 1)
    else:
        base = fmt[1]
        for i in range(8):
            a = base + i*160*208*2
            yield 'girl', a, rgb(np.frombuffer(d[a:a + 160*208*2], '>u2').reshape(208, 160)[::-1] >> 1)

def main():
    zipdir, outdir = sys.argv[1], sys.argv[2]
    names = sys.argv[3:] or list(SETS)
    index = {}
    for n in names:
        d = build(zipdir, n)
        os.makedirs(os.path.join(outdir, n), exist_ok=True)
        k = {'girl': 0, 'screen': 0}; index[n] = []
        for kind, a, im in pictures(d, SETS[n][2]):
            k[kind] += 1
            fn = '%s%02d.png' % ('' if kind == 'girl' else 'screen_', k[kind])
            im.save(os.path.join(outdir, n, fn))
            index[n].append({'file': fn, 'kind': kind, 'addr': '%06x' % a, 'size': list(im.size)})
        print(n, k, flush=True)
    json.dump(index, open(os.path.join(outdir, 'index_%s.json' % '_'.join(names) if sys.argv[3:] else 'index.json'), 'w'), indent=1)

if __name__ == '__main__':
    main()
