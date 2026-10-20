#!/usr/bin/env python3
# dynduke_build.py outdir : JTDYNDUKE images + MRAs for Dynamite Duke (user's merged dynduke.zip)
# Image after the 4-byte header (byte 0 bit 0 = Double Dynamites I/O map): master V30 0 (0x60000, little endian
# words), slave V30 0x60000, Z80 0x80000 (8.w8 + its first half again), OKI 0xa0000, characters 0xb0000
# (32-bit rows: ROM 9 word, ROM 10 word), background 0x100000 (64-bit rows: one word per third, the third
# repeated), foreground 0x300000 (32-bit rows: first half word, second half word), sprites 0x400000.
import sys, os, zipfile, hashlib
S = '/tmp/claude-0/-home-claude/183009bc-02e0-578a-b0ba-00b6083aaf64/scratchpad'
DIPS = [
    '<dip name="Coin Mode" bits="0" ids="Mode 2,Mode 1"/>',
    '<dip name="Coinage (Mode 1)" bits="1,2,3,4" ids="Free Play,-,-,-,-,-,-,-,-,-,-,-,4C/1C,3C/1C,2C/1C,1C/1C"/>',
    '<dip name="Starting Coin" bits="5" ids="X 2,Normal"/>',
    '<dip name="Bonus D.Punch" bits="10,11" ids="120K 120K+,120K 100K+,100K 100K+,80K 100K+"/>',
    '<dip name="Difficulty" bits="12,13" ids="Hardest,Hard,Easy,Normal"/>',
    '<dip name="Allow Continue" bits="14" ids="Off,On"/>',
    '<dip name="Demo Sounds" bits="15" ids="Off,On"/>',
]
SETS = {
    'dynduke':   ('Dynamite Duke (Europe, 03SEP89)', ('dde3.e8', '95336279'),           ('dde4.e7', 'eb2d8fea'),           'Europe'),
    'dyndukea':  ('Dynamite Duke (Europe, 25JUL89)', ('dyndukea/3.e8', 'a56f8692'),     ('dyndukea/4e.e7', '384c0635'),    'Europe'),
    'dyndukej':  ('Dynamite Duke (Japan, 03SEP89)',  ('dyndukej/3.e8', '98b9d243'),     ('dyndukej/4.e7', '4f575177'),     'Japan'),
    'dyndukeja': ('Dynamite Duke (Japan, 25JUL89)',  ('dyndukeja/3.e8', '2f06ddce'),    ('dyndukeja/4j.e7', '63092078'),   'Japan'),
    'dyndukeu':  ('Dynamite Duke (US, 25JUL89)',     ('dyndukea/3.e8', 'a56f8692'),     ('dyndukeu/dd4.ef7', 'ee4b87b3'),  'USA'),
}
out = sys.argv[1]; os.makedirs(f'{out}/mra', exist_ok=True)
z = zipfile.ZipFile(f'{S}/userzips/dynduke.zip')
rd = lambda n: z.read(n)
crc = lambda n: '%08x' % z.getinfo(n).CRC
nl = '\n'

def P(n, extra=''):
    return f'<part name="{n.split("/")[-1]}" crc="{crc(n)}"{extra}/>'

def il(roms, lanes, width):   # interleave: each ROM gives `width` bytes per row, at its lane
    n = len(roms[0]) // width
    row = len(lanes) and max(lanes) + 1
    o = bytearray()
    for k in range(n):
        r = bytearray(row * width)
        for rom, lane in zip(roms, lanes): r[lane*width:(lane+1)*width] = rom[k*width:(k+1)*width]
        o += r
    return bytes(o)

def ilx(names, lanes, width, outbytes):
    maps = []
    for lane in lanes:
        digits = ['0'] * outbytes
        for b in range(width): digits[outbytes - 1 - (lane*width + b)] = '%x' % (b + 1)
        maps.append(''.join(digits))
    return [f'<interleave output="{outbytes*8}">'] + ['    ' + P(n, f' map="{m}"') for n, m in zip(names, maps)] + ['</interleave>']

for name, (title, e3, o4, region) in SETS.items():
    e3, o4 = e3[0], o4[0]
    img = bytearray(b'\0\0\0\0')
    parts = ['<part>00 00 00 00</part>']
    def add(data, xml):
        img.extend(data); parts.extend(xml)
    def pad(to):
        n = to + 4 - len(img); assert n >= 0, hex(len(img))
        if n: img.extend(b'\xff' * n); parts.append(f'<part repeat="0x{n:x}">FF</part>')
    def il16(a, b):
        add(il([rd(a), rd(b)], [0, 1], 1), ilx([a, b], [0, 1], 1, 2))
    il16('1.cd8', '2.cd7'); il16(e3, o4); il16('5.p8', '6.p7')
    snd = rd('8.w8')
    add(snd + snd[:0x8000], [P('8.w8'), P('8.w8', ' length="0x8000"')])
    pad(0xa0000); add(rd('7.x10'), [P('7.x10')])
    add(il([rd('9.5k'), rd('10.34k')], [0, 1], 2), ilx(['9.5k', '10.34k'], [0, 1], 2, 4))
    pad(0x100000)
    for t in (['dd.a2', 'dd.c2', 'dd.de3'], ['dd.b2', 'dd.d2', 'dd.ef3']):
        add(il([rd(t[0]), rd(t[1]), rd(t[2]), rd(t[2])], [0, 1, 2, 3], 2), ilx([t[0], t[1], t[2], t[2]], [0, 1, 2, 3], 2, 8))
    for a, b in (('dd.mn3', 'dd.n45'), ('dd.mn4', 'dd.mn5')):
        add(il([rd(a), rd(b)], [0, 1], 2), ilx([a, b], [0, 1], 2, 4))
    for a, b in (('dd.n1', 'dd.n2'), ('dd.m1', 'dd.m2'), ('dd.e1', 'dd.e2'), ('dd.f1', 'dd.f2')):
        il16(a, b)
    assert len(img) == 0x600004, hex(len(img))
    open(f'{out}/{name}.rom', 'wb').write(img)
    md5 = hashlib.md5(img).hexdigest()
    mra = f'''<!-- {title} on JTDYNDUKE, a personal MiSTer core for Seibu's Dynamite Duke board (MAME dynduke.cpp),
     built on JTFRAME by Jose Tejada (jotego), with the V30 CPU model of the MiSTer Irem M72 core by Martin Donlon
     (GPL-2). The ROM is assembled from your own MAME zip, unmodified. Requires jtdynduke.rbf. -->
<misterromdescription>
    <name>{title} (JTDYNDUKE)</name>
    <setname>{name}</setname>
    <rotation>horizontal</rotation>
    <mameversion>0264</mameversion>
    <year>1989</year>
    <manufacturer>{'Seibu Kaihatsu (Fabtek license)' if region == 'USA' else 'Seibu Kaihatsu'}</manufacturer>
    <players>2</players>
    <rbf>jtdynduke</rbf>
    <joystick>8</joystick>
    <region>{region}</region>
    <rom index="0" zip="dynduke.zip" md5="None">
{nl.join('        ' + p for p in parts)}
    </rom>
    <rom index="1">
        <part>00</part>
    </rom>
    <switches page_id="1" page_name="Switches" base="16" default="ff,f7">
{nl.join('        ' + d for d in DIPS)}
    </switches>
    <buttons names="Button 1,Button 2,Button 3,Start,Coin,Core credits" default="A,B,X,Start,Select,-" count="3"/>
</misterromdescription>
'''
    open(f"{out}/mra/{title} (JTDYNDUKE).mra", 'w').write(mra)
    open(f"{out}/{name}.md5", "w").write(md5)
    print(name, md5)
