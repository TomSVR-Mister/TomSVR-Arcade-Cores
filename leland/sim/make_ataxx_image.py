"""Build the flat Ataxx download image (16-byte header + canonical region layout).

usage: python make_ataxx_image.py ataxx.zip ataxx_image.bin
"""
import sys, zipfile

zf = zipfile.ZipFile(sys.argv[1])
rom = lambda n: zf.read(n)

def pad(buf, n):
    assert len(buf) <= n, (len(buf), n)
    return buf + bytes(n - len(buf))

def interleave(lo, hi):
    out = bytearray(len(lo) * 2)
    out[0::2] = lo
    out[1::2] = hi
    return bytes(out)

hdr = bytes([0x4C, 0x01, 0x04, 0x03, 0x03, 0x02]) + bytes(10)

master = pad(rom("e-302-31005-05.u38"), 0x100000)
slave = pad(rom("e-302-31012-01.u111") + rom("e-302-31013-01.u112") +
            rom("e-302-31014-01.u113"), 0x200000)

s_a = interleave(rom("e-302-31001-01.u1"), rom("e-302-31003-01.u15"))
s_b = interleave(rom("e-302-31002-01.u2"), rom("e-302-31004-01.u16"))
sound = pad(bytes(0x20000) + s_a + s_b + bytes(0x20000) + s_b, 0x100000)

gfx_names = ["e-302-31006-01.u98", "e-302-31007-01.u99", "e-302-31008-01.u100",
             "e-302-31009-01.u101", "e-302-31010-01.u102", "e-302-31011-01.u103"]
# 8-byte tile rows, as the MRA's 64-bit interleave lays them down: plane0..plane5 on lanes 0-5,
# plane 0 repeated on the two pad lanes
planes = [rom(n) for n in gfx_names]
rows = bytearray(8 * len(planes[0]))
for lane in range(8):
    rows[lane::8] = planes[lane if lane < 6 else 0]
gfx = pad(bytes(rows), 0x300000)

eeprom = rom("eeprom-ataxx.bin")

img = hdr + master + slave + sound + gfx + pad(eeprom, 0x100)
assert len(img) - 16 == 0x700100
open(sys.argv[2], "wb").write(img)
print("wrote", sys.argv[2], len(img), "bytes")
