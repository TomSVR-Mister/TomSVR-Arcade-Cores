"""Build the flat Indy Heat download image (16-byte header + canonical region layout).

usage: python make_indyheat_image.py indyheat.zip indyheat_image.bin
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

hdr = bytes([0x4C, 0x01, 0x05, 0x04, 0x00, 0x0E]) + bytes(10)

code = b"".join(rom(n) for n in ("e-302-33019-01.u64", "e-302-33020-01.u65",
                                 "e-302-33017-01.u66", "e-302-33018-01.u67"))
xrom = interleave(rom("e-302-33015-01.u68"), rom("e-302-33016-01.u69"))
master = pad(code + xrom, 0x100000)

u152, u153 = rom("e-302-33008-01.u152"), rom("e-302-33009-01.u153")
slave_rom = (rom("e-302-33007-01.u151") + u152[:0x20000] + u153[:0x20000] +
             b"".join(rom(n) for n in ("e-302-33010-01.u154", "e-302-33011-01.u155",
                                       "e-302-33012-01.u156", "e-302-33013-01.u157",
                                       "e-302-33014-01.u158")) +
             bytes(0x20000) + u152[0x20000:] + u153[0x20000:])
assert len(slave_rom) == 0x160000
slave = pad(pad(slave_rom, 0x180000) + rom("e-302-33025-01.u8") + rom("e-302-33026-01.u9"), 0x200000)

s_a = interleave(rom("e-302-33024-01.u6"), rom("e-302-33021-01.u3"))
s_b = interleave(rom("e-302-33023-01.u5"), rom("e-302-33022-01.u4"))
sound = pad(bytes(0x20000) + s_a + s_b + bytes(0x20000) + s_b, 0x100000)

gfx_names = ["e-302-33001-01.u145", "e-302-33002-01.u146", "e-302-33003-01.u147",
             "e-302-33004-01.u148", "e-302-33005-01.u149", "e-302-33006-01.u150"]
# 8-byte tile rows, as the MRA's 64-bit interleave lays them down: plane0..plane5 on lanes 0-5,
# plane 0 repeated on the two pad lanes
planes = [rom(n) for n in gfx_names]
rows = bytearray(8 * len(planes[0]))
for lane in range(8):
    rows[lane::8] = planes[lane if lane < 6 else 0]
gfx = pad(bytes(rows), 0x300000)

eeprom = rom("eeprom-indyheat.bin")

img = hdr + master + slave + sound + gfx + pad(eeprom, 0x100)
assert len(img) - 16 == 0x700100
open(sys.argv[2], "wb").write(img)
print("wrote", sys.argv[2], len(img), "bytes")
