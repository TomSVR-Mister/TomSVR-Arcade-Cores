#!/usr/bin/env python3
"""Zip & Zap (Barko, 1995) for the jtcomad core (COMAD=1).
   Hardware differences from the Gals Panic board the core implements, and what is patched:
   - work RAM c80000-c8ffff        -> native on jtcomad (no change)
   - sprite RAM 0x700000 (VU-002)  -> shadow 0x702000, converted to Pandora every vblank (asm/conv_zz.s)
   - OKI at c00000                 -> 0xa80001
   - IRQ4 (task tick + inputs)     -> called from the new vblank handler (Gals Panic never raises IRQ4)
   - OKI "wait until voice started" poll removed (MAME returns random values there)"""
import os, sys, struct, subprocess
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from port import *
from games_c0 import asm, one
assert COMAD

SHADOW, FLAGS, MARK = 0x702000, 0x703000, 0x703200
RAMBASE = 0x53c000
CONV = 0xc0000
def ram_map(v):
    if 0xc80000 <= v < 0xc84000: return RAMBASE + v - 0xc80000
spr_map = lambda v: SHADOW + (v - 0x700000) if 0x700000 <= v < 0x701000 else None

DIPS_ZZ = [
    '<dip name="Additional Obstacles" bits="1" ids="On,Off"/>',
    '<dip name="Lives" bits="2,3" ids="1,4,2,3"/>',
    '<dip name="Coinage" bits="8,9" ids="3C/1C,2C/1C,1C/2C,1C/1C"/>',
    '<dip name="Select Player Mode" bits="10" ids="Off,On"/>',
    '<dip name="Demo Sounds" bits="11" ids="Off,On"/>',
    '<dip name="Level Skip with Button 2" bits="14" ids="On,Off"/>',
]
Z = 'zipzap/'
SETS = {
  'zipzap':  dict(title='Zip & Zap (Explicit)', zips=('zipzap.zip',), prog=(Z + 'ue17.bin', Z + 'ud17.bin'),
                  data=[(Z + '937.bin', Z + '941.bin'), (Z + '936.bin', Z + '940.bin'), (Z + '934.bin', Z + '939.bin'), (Z + '938.bin', Z + '942.bin')],
                  spr=Z + 'u5.bin', oki=[Z + 'snd.bin', Z + 'snd.bin']),
  'zipzapa': dict(title='Zip & Zap (Less Explicit)', zips=('zipzapa.zip', 'zipzap.zip'), prog=(Z + 'zipzapa/31.ue17', Z + 'zipzapa/30.ud17'),
                  data=[(Z + 'zipzapa/37.rd2b', Z + 'zipzapa/33.rd2a'), (Z + 'zipzapa/38.rd3b', Z + 'zipzapa/34.rd3a'),
                        (Z + 'zipzapa/39', Z + 'zipzapa/35'), (Z + 'zipzapa/36.rd1b', Z + 'zipzapa/32.rd1a')],
                  spr=Z + 'u5.bin', oki=[Z + 'zipzapa/29.ub6'] * 4 + [Z + 'zipzapa/28.uc6']),
}

def build(name, xoff=0, yoff=0):
    a = SETS[name]
    p = Port(name, [(0, 'il', a['prog'])] + [(0x100000 * (i + 1), 'il', d) for i, d in enumerate(a['data'])], 0x500000)
    p.identity_layout()
    refs = f'{BASE}/refs_{name}.json'
    orig3, orig4 = p.getl(27 * 4), p.getl(28 * 4)
    assert p.img[orig4:orig4 + 2] == b'\x60\x00', 'IRQ4 vector is a bra.w'
    orig4 = orig4 + 2 + struct.unpack('>h', p.img[orig4 + 2:orig4 + 4])[0]
    # work RAM stays at c80000: jtcomad maps native Comad work RAM there
    p.relocate(refs, spr_map, 'SPR', coords=False)
    p.relocate(refs, lambda v: OKIA, 'OKI', coords=False)
    # OKI "wait until the voice has started" (btst #0 ; beq.s back) -> fall through
    h = p.find(bytes.fromhex('1039') + L(OKIA) + bytes.fromhex('0800000067f4')); assert len(h) == 1, h
    p.put(h[0] + 10, bytes.fromhex('4e71'), 'okiwait')
    # new vblank handler in the extension ROM
    code, sym = asm(name + '_conv', 'conv_zz.s', dict(ORIG3=orig3, ORIG4=orig4, SHADOW=SHADOW, FLAGS=FLAGS, MARK=MARK,
                                                      XOFF=xoff & 0xffff, YOFF=yoff & 0xffff))
    # placed in the padding after the program (inside the original 5 MB ROM space, so MAME's own zipzap driver can run
    # the patched image as a test bench); IRQ4 vector -> an rte, since the handler is now called from vblank
    assert p.unpatched[CONV:CONV + 0x400] == b'\xff' * 0x400
    p.put(CONV, code, 'vblank handler + sprite converter')
    p.put(27 * 4, L(CONV + sym['irq3']), 'IRQ3 vector')
    rte = p.find(bytes.fromhex('4e73'), 0x400, 0x500)[0]
    p.put(28 * 4, L(rte), 'IRQ4 vector -> rte')
    p.log.append('IRQ3 %06x IRQ4 %06x -> new handler %06x' % (orig3, orig4, CONV))
    p.save_image()
    fn = p.mra(a['title'], name, list(a['zips']), a['oki'], [a['spr']], DIPS_ZZ, rotate_vertical=True, year='1995',
                 manufacturer='Barko Corp', comment=';\n     Zip &amp; Zap hardware differences patched: RAM, OKI, IRQ4 task tick, bootleg VU-002 sprite list')
    body = open(fn).read().replace('Zip & Zap', 'Zip &amp; Zap')          # XML escape in <name> and the comment
    open(fn, 'w').write(body)
    return fn

if __name__ == '__main__':
    import os
    for n in (sys.argv[1:] or SETS):
        print(build(n, int(os.environ.get('XOFF', '0')), int(os.environ.get('YOFF', '0'))))
