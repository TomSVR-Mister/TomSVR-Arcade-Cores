#!/usr/bin/env python3
"""bg_reference.py -- software reference model of the Leland background
tilemap (MAME leland_v.cpp semantics), used to pixel-diff leland_video_tb's
PPM dumps against ground truth computed directly from the ROM files.

Implements exactly:
  - leland_scan: idx = (col&0xff) | ((row&0x1f)<<8) | ((row&0xe0)<<9)
  - prom bank:   +(BIT(gfxbank,3) << 13)
  - tile code:   prom_byte | ((idx>>7)&0x300) | ((gfxbank>>4)&3)<<10
  - 3 bitplanes at plane*0x8000 + code*8 + row_in_tile, pixel x = bit (7-x);
    the FIRST third of bg_gfx is the MSB and the LAST third the LSB (leland_layout
    lists planeoffsets ascending; decode() weights them 1 << (planes-1-plane))
  - pen = (prom_byte>>5)*8 + {p2,p1,p0}
Output pixels are pen<<2 grayscale, identical encoding to the TB's dump.
"""
import sys
from PIL import Image

def load(fn):
    with open(fn, "rb") as f:
        return f.read()

def build_roms(simdir="."):
    gfx = bytearray()
    for fn in ["03-22105-02.u93", "03-22106-02.u94", "03-22107-02.u95"]:
        gfx += load(f"{simdir}/{fn}")
    assert len(gfx) == 0x18000
    prom = bytearray(0x20000)
    for fn, base in [("03-22104-01.u92", 0x4000), ("03-22102-01.u69", 0x8000),
                     ("03-22103-02.u90", 0x14000), ("03-22101-02.u67", 0x18000)]:
        d = load(f"{simdir}/{fn}")
        prom[base:base+len(d)] = d
    return bytes(gfx), bytes(prom)

def render(gfx, prom, scroll_x, scroll_y, gfxbank, w=320, h=240):
    img = Image.new("L", (w, h))
    px = img.load()
    prom_bank = ((gfxbank >> 3) & 1) << 13
    char_bank = ((gfxbank >> 4) & 3) << 10
    for sy in range(h):
        ey = (sy + scroll_y) & 0x7FF
        row = ey >> 3
        riy = ey & 7
        for sx in range(w):
            ex = (sx + scroll_x) & 0x7FF
            col = ex >> 3
            cix = ex & 7
            idx = (col & 0xFF) | ((row & 0x1F) << 8) | ((row & 0xE0) << 9)
            pb = prom[idx | prom_bank]
            code = pb | ((idx >> 7) & 0x300) | char_bank
            a = code * 8 + riy
            bit = 7 - cix
            # leland_layout lists planeoffsets ascending {RGN_FRAC(0,3),
            # RGN_FRAC(1,3), RGN_FRAC(2,3)} while gfx_element::decode() weights
            # them 1 << (planes-1-plane), so the FIRST third of bg_gfx (u93) is
            # the MSB and the LAST (u95) is the LSB.
            p2 = (gfx[a] >> bit) & 1
            p1 = (gfx[0x8000 + a] >> bit) & 1
            p0 = (gfx[0x10000 + a] >> bit) & 1
            pen = ((pb >> 5) << 3) | (p2 << 2) | (p1 << 1) | p0
            px[sx, sy] = pen << 2
    return img

def diff(ref, dump_path):
    d = Image.open(dump_path).convert("L")
    if d.size != ref.size:
        return None
    rp, dp = ref.load(), d.load()
    n = 0
    first = []
    for y in range(ref.size[1]):
        for x in range(ref.size[0]):
            if rp[x, y] != dp[x, y]:
                n += 1
                if len(first) < 12:
                    first.append((x, y, rp[x, y] >> 2, dp[x, y] >> 2))
    return n, first

if __name__ == "__main__":
    gfx, prom = build_roms()
    cases = [
        ("race",    0x140, 0x188, 0x03),
        ("winners", 0x140, 0x1d8, 0x3b),
        ("track2",  0x280, 0x190, 0x1b),
        ("finex3",  0x143, 0x188, 0x03),
        ("finex5",  0x145, 0x188, 0x03),
        ("finex6",  0x146, 0x188, 0x03),
        ("finex7",  0x147, 0x188, 0x03),
        ("switch_race_to_winners", 0x140, 0x1d8, 0x3b),
    ]
    for name, sx, sy, gb in cases:
        ref = render(gfx, prom, sx, sy, gb)
        ref.save(f"ref_{name}.png")
        try:
            n, first = diff(ref, f"frame_dump_{name}.ppm")
            total = 320 * 240
            print(f"{name:26s} diff={n}/{total} ({100.0*n/total:.2f}%)"
                  + ("" if not first else f"  first: {first}"))
        except FileNotFoundError:
            print(f"{name:26s} dump not present yet")
