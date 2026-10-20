#!/usr/bin/env python3
# make_logo.py outdir : the TomSVR menu background for JTFRAME's OSD (replaces jtframe's logodata.hex/logomap.hex).
# The OSD logo is a 256x128 map of 8x8 tiles, 2 bits per pixel (0 = see-through, 1 = white, 2 = red),
# at most 128 different tiles. Words are { plane 1, plane 0 }, leftmost pixel in each byte's MSB.
import sys, os
from PIL import Image, ImageDraw, ImageFont
FONT = '/usr/share/fonts/opentype/inter/InterDisplay-BlackItalic.otf'
if not os.path.exists(FONT): FONT = '/usr/share/fonts/opentype/inter/InterDisplay-BoldItalic.otf'
out = sys.argv[1]; os.makedirs(out, exist_ok=True)

def render(size, shadow):
    im = Image.new('L', (256, 128), 0)
    d = ImageDraw.Draw(im)
    f = ImageFont.truetype(FONT, size)
    text = 'TomSVR'
    x0, y0, x1, y1 = d.textbbox((0, 0), text, font=f)
    ox = (256 - (x1 - x0) - shadow) // 2 - x0
    oy = (128 - (y1 - y0) - shadow) // 2 - y0
    d.text((ox + shadow, oy + shadow), text, font=f, fill=2)
    d.text((ox, oy), text, font=f, fill=1)
    return im

def tiles_of(im):
    px = im.load(); m = []
    for r in range(16):
        for c in range(32):
            m.append(tuple(px[c*8+x, r*8+y] for y in range(8) for x in range(8)))
    return m

SIZE = int(sys.argv[2]) if len(sys.argv) > 2 else 56
size = SIZE
im = render(size, 4)
m = tiles_of(im)
# too many different tiles: replace the least used tile by its closest neighbour until 128 are left
from collections import Counter
def dist(a, b): return sum(x != y for x, y in zip(a, b))
while len(set(m)) > 128:
    cnt = Counter(m)
    rare = min(cnt, key=lambda t: (cnt[t], -dist(t, (0,)*64)))
    best = min((t for t in cnt if t != rare), key=lambda t: dist(t, rare))
    m = [best if t == rare else t for t in m]
px = im.load()
for k, t in enumerate(m):
    r, c = divmod(k, 32)
    for i, v in enumerate(t): px[c*8 + i % 8, r*8 + i // 8] = v
uniq = sorted(set(m), key=lambda t: (any(t), t))   # the empty tile first
assert len(uniq) <= 128 and not any(uniq[0])
idx = {t: k for k, t in enumerate(uniq)}
with open(f'{out}/logomap.hex', 'w') as f:
    for t in m: f.write('%02X\n' % idx[t])
with open(f'{out}/logodata.hex', 'w') as f:
    for k in range(128):
        t = uniq[k] if k < len(uniq) else (0,) * 64
        for y in range(8):
            row = t[y*8:y*8+8]
            p0 = sum(((v >> 0) & 1) << (7 - x) for x, v in enumerate(row))
            p1 = sum(((v >> 1) & 1) << (7 - x) for x, v in enumerate(row))
            f.write('%04X\n' % (p1 << 8 | p0))
pal = {0: (0, 0, 0), 1: (255, 255, 255), 2: (255, 0, 0)}
prev = Image.new('RGB', (256, 128)); prev.putdata([pal[px[x, y]] for y in range(128) for x in range(256)])
prev.resize((512, 256), Image.NEAREST).save(f'{out}/logo_preview.png')
print('font size', size, len(uniq), 'tiles')
