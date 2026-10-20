#!/usr/bin/env python3
# xexex_build.py outdir : JTXEXEX images + MRAs for Xexex / Orius (user's merged xexex.zip)
# Image: 68000 program 0 (1 MB: 000000-07FFFF then 100000-17FFFF, 16-bit big endian words), Z80 0x100000,
# K054539 samples 0x120000, K056832 tiles 0x420000 (LOAD32_WORD), K053250 0x620000,
# K053246 sprites 0x6A0000 (LOAD64_WORD). The ER5911 default contents go in rom index 2.
import sys, os, zipfile, hashlib
S = '/tmp/claude-0/-home-claude/183009bc-02e0-578a-b0ba-00b6083aaf64/scratchpad'
SETS = {
    'xexex':  ('Xexex (ver EAA)', '067eaa01.16d',        '067eaa02.16f',        '067eaa05.4e',        'er5911.19b',        'Europe'),
    'orius':  ('Orius (ver UAA)', 'orius/067uaa01.16d',  'orius/067uaa02.16f',  '067eaa05.4e',        'orius/er5911.19b',  'USA'),
    'xexexa': ('Xexex (ver AAA)', 'xexexa/067aaa01.16d', 'xexexa/067aaa02.16f', '067eaa05.4e',        'xexexa/er5911.19b', 'Asia'),
    'xexexj': ('Xexex (ver JAA)', 'xexexj/067jaa01.16d', 'xexexj/067jaa02.16f', 'xexexj/067jaa05.4e', 'xexexj/er5911.19b', 'Japan'),
}
out = sys.argv[1]; os.makedirs(f'{out}/mra', exist_ok=True)
z = zipfile.ZipFile(f'{S}/userzips/xexex.zip')
rd = lambda n: z.read(n)
crc = lambda n: '%08x' % z.getinfo(n).CRC
P = lambda n, extra='': f'<part name="{n.split("/")[-1]}" crc="{crc(n)}"{extra}/>'
nl = '\n'

def il16(e, o):    # 68000: big endian words, even ROM in the upper byte
    a, b = rd(e), rd(o)
    return bytes(x for k in range(len(a)) for x in (b[k], a[k]))

def ilw(names):    # LOAD32_WORD / LOAD64_WORD: one 16-bit word from each ROM in turn
    rs = [rd(n) for n in names]
    o = bytearray()
    for k in range(0, len(rs[0]), 2):
        for r in rs: o += r[k:k+2]
    return bytes(o)

tiles = ilw(['067b14.1n', '067b13.2n'])
objs  = ilw(['067b12.17n', '067b11.19n', '067b10.20n', '067b09.22n'])

for name, (title, ev, od, snd, eep, region) in SETS.items():
    img = il16(ev, od) + il16('067b03.13d', '067b04.13f')
    img += rd(snd) + rd('067b06.3e') + rd('067b07.1e')
    img += tiles + rd('067b08.22f') + objs
    assert len(img) == 0xAA0000, hex(len(img))
    parts = ['<interleave output="16">', '    ' + P(ev, ' map="10"'), '    ' + P(od, ' map="01"'), '</interleave>',
             '<interleave output="16">', '    ' + P('067b03.13d', ' map="10"'), '    ' + P('067b04.13f', ' map="01"'), '</interleave>',
             P(snd), P('067b06.3e'), P('067b07.1e'),
             '<interleave output="32">', '    ' + P('067b14.1n', ' map="0021"'), '    ' + P('067b13.2n', ' map="2100"'), '</interleave>',
             P('067b08.22f'),
             '<interleave output="64">',
             '    ' + P('067b12.17n', ' map="00000021"'), '    ' + P('067b11.19n', ' map="00002100"'),
             '    ' + P('067b10.20n', ' map="00210000"'), '    ' + P('067b09.22n', ' map="21000000"'),
             '</interleave>']
    open(f'{out}/{name}.rom', 'wb').write(img)
    open(f'{out}/{name}.eep', 'wb').write(rd(eep))
    md5 = hashlib.md5(img).hexdigest()
    mra = f'''<!-- {title} on JTXEXEX, a personal MiSTer core for Konami's Xexex board (MAME xexex.cpp),
     built on JTFRAME and jotego's CPU and sound models. The ROM is assembled from your own MAME zip, unmodified.
     Game settings live in the EEPROM: change them in the game's test mode (hold the test button at boot).
     Requires jtxexex.rbf. -->
<misterromdescription>
    <name>{title} (JTXEXEX)</name>
    <setname>{name}</setname>
    <rotation>horizontal</rotation>
    <mameversion>0264</mameversion>
    <year>1991</year>
    <manufacturer>Konami</manufacturer>
    <players>2</players>
    <rbf>jtxexex</rbf>
    <joystick>8-way</joystick>
    <region>{region}</region>
    <rom index="0" zip="xexex.zip" md5="None">
{nl.join('        ' + p for p in parts)}
    </rom>
    <rom index="2" zip="xexex.zip" md5="None">
        {P(eep)}
    </rom>
    <nvram index="2" size="128"/>
    <buttons names="Shot,Flint,Start,Coin,Core credits" default="A,B,Start,Select,-" count="2"/>
</misterromdescription>
'''
    open(f"{out}/mra/{title} (JTXEXEX).mra", 'w').write(mra)
    open(f"{out}/{name}.md5", "w").write(md5)
    print(name, md5)
