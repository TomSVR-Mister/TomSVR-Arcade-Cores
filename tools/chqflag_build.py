#!/usr/bin/env python3
# chqflag_build.py outdir : JTCHQFLAG images + MRAs for Chequered Flag (user's merged chqflag.zip)
# Image: 052001 program 0 (320 kB), Z80 0x80000, 051316 #1 (4 bpp) 0x88000, 007232 #1 0x100000,
# 007232 #2 0x180000, 051316 #2 (8 bpp) 0x200000, sprites 0x400000 (32-bit words, bytes reversed).
import sys, os, zipfile, hashlib
S = '/tmp/claude-0/-home-claude/183009bc-02e0-578a-b0ba-00b6083aaf64/scratchpad'
COIN = 'Free Play,4C/3C,4C/1C,3C/4C,3C/2C,3C/1C,2C/5C,2C/3C,2C/1C,1C/7C,1C/6C,1C/5C,1C/4C,1C/3C,1C/2C,1C/1C'
DIPS = [
    f'<dip name="Coin A" bits="0,1,2,3" ids="{COIN}"/>',
    f'<dip name="Coin B" bits="4,5,6,7" ids="{COIN.replace("Free Play", "Invalid")}"/>',
    '<dip name="Difficulty" bits="13,14" ids="Very Difficult,Difficult,Normal,Easy"/>',
    '<dip name="Demo Sounds" bits="15" ids="On,Off"/>',
    '<dip name="Title" bits="17" ids="Checkered Flag,Chequered Flag"/>',
    '<dip name="Service Mode" bits="18" ids="On,Off"/>',
]
SETS = {'chqflag': ('Chequered Flag', '717h02', 'World'), 'chqflagj': ('Chequered Flag (Japan)', 'chqflagj/717j02.bin', 'Japan')}
out = sys.argv[1]; os.makedirs(f'{out}/mra', exist_ok=True)
z = zipfile.ZipFile(f'{S}/userzips/chqflag.zip')
rd = lambda n: z.read(n)
crc = lambda n: '%08x' % z.getinfo(n).CRC
P = lambda n, extra='': f'<part name="{n.split("/")[-1]}" crc="{crc(n)}"{extra}/>'
pad = lambda b, n: b + bytes([0xff]) * (n - len(b))
nl = '\n'
for name, (title, prog2, region) in SETS.items():
    img = rd('717e10') + rd(prog2)
    img = pad(img, 0x80000) + pad(rd('717e01') + rd('717e06.n16'), 0x80000)
    img += rd('717e03') + rd('717e09')
    img += rd('717e07.l20') + rd('717e08.l22') + rd('717e11.n20') + rd('717e12.n22')
    img += bytes([0xff]) * 0x100000
    a, b = rd('717e04'), rd('717e05')
    spr = bytearray()
    for k in range(0, len(a), 2): spr += bytes([b[k+1], b[k], a[k+1], a[k]])
    img += spr
    assert len(img) == 0x500000, hex(len(img))
    parts = [P('717e10'), P(prog2), '<part repeat="0x30000">FF</part>', P('717e01'), P('717e06.n16'), '<part repeat="0x58000">FF</part>',
             P('717e03'), P('717e09'), P('717e07.l20'), P('717e08.l22'), P('717e11.n20'), P('717e12.n22'),
             '<part repeat="0x100000">FF</part>',
             '<interleave output="32">', '    ' + P('717e04', ' map="1200"'), '    ' + P('717e05', ' map="0012"'), '</interleave>']
    open(f'{out}/{name}.rom', 'wb').write(img)
    md5 = hashlib.md5(img).hexdigest()
    mra = f'''<!-- {title} on JTCHQFLAG, a personal MiSTer core for Konami's Chequered Flag board (MAME chqflag.cpp),
     built on JTFRAME and jotego's Konami chip models. The ROM is assembled from your own MAME zip, unmodified.
     Controls: button 1 accelerates, button 2 brakes, button 3 shifts gear (toggle). Steer with left/right
     or the left analog stick. Requires jtchqflag.rbf. -->
<misterromdescription>
    <name>{title} (JTCHQFLAG)</name>
    <setname>{name}</setname>
    <rotation>vertical (ccw)</rotation>
    <mameversion>0264</mameversion>
    <year>1988</year>
    <manufacturer>Konami</manufacturer>
    <players>1</players>
    <rbf>jtchqflag</rbf>
    <joystick>2-way horizontal</joystick>
    <region>{region}</region>
    <rom index="0" zip="chqflag.zip" md5="None">
{nl.join('        ' + p for p in parts)}
    </rom>
    <rom index="1">
        <part>01 00</part>
    </rom>
    <switches page_id="1" page_name="Switches" base="16" default="ff,5f,0f">
{nl.join('        ' + d for d in DIPS)}
    </switches>
    <buttons names="Accelerate,Brake,Shift,Start,Coin,Core credits" default="A,B,X,Start,Select,-" count="3"/>
</misterromdescription>
'''
    open(f"{out}/mra/{title} (JTCHQFLAG).mra", 'w').write(mra)
    open(f"{out}/{name}.md5", "w").write(md5)
    print(name, md5)
