#!/usr/bin/env python3
# wrally_build.py outdir : JTWRALLY images + MRAs for World Rally (user's merged wrally.zip)
# Image: 68000 program 0 (1 MB, byte swapped as JTFRAME expects), OKI 0x100000 (1 MB),
# graphics 0x200000 (2 MB of 32-bit words {plane3..plane0} = {hi half odd, hi half even, lo half odd, lo half even}),
# DS5002FP program 0x400000 (32 kB). Sets and CRCs are read from MAME's wrally.cpp (REF).
import sys, os, re, zipfile, hashlib
S = '/tmp/claude-0/-home-claude/183009bc-02e0-578a-b0ba-00b6083aaf64/scratchpad'
REF = f'{S}/ref/wrally.cpp'
src = open(REF).read()
DIPS = [
    '<dip name="Difficulty" bits="0,1" ids="Hardest,Hard,Easy,Normal"/>',
    '<dip name="Number of Joysticks" bits="2" ids="1,2"/>',
    '<dip name="Control" bits="3,4" ids="Optical Wheel,invalid,Pot Wheel,Joystick"/>',
    '<dip name="Demo Sounds" bits="5" ids="On,Off"/>',
    '<dip name="Cabinet" bits="6" ids="Cocktail,Upright"/>',
    '<dip name="Service Mode" bits="7" ids="On,Off"/>',
    '<dip name="Coin A" bits="8,9,10" ids="3C/4C,2C/3C,1C/6C,1C/5C,1C/4C,1C/3C,1C/2C,1C/1C"/>',
    '<dip name="Coin B" bits="11,12,13" ids="4C/3C,3C/2C,6C/1C,5C/1C,4C/1C,3C/1C,2C/1C,1C/1C"/>',
    '<dip name="Credit Config" bits="14" ids="Start 2C/Cont 1C,Start 1C/Cont 1C"/>',
    '<dip name="Free Play" bits="15" ids="On,Off"/>',
]
games = {m[0]: (m[1], m[2]) for m in re.findall(r'GAME\( 1993, (\w+),.*?ROT0, (?:u8)?"([^"]+)", "([^"]+)"', src)}
out = sys.argv[1]; os.makedirs(f'{out}/mra', exist_ok=True)
z = zipfile.ZipFile(f'{S}/userzips/wrally.zip'); by = {'%08x' % i.CRC: i for i in z.infolist()}
nl = '\n'
for name, (man, title) in games.items():
    body = re.search(r'ROM_START\( %s \)(.*?)ROM_END' % name, src, re.S).group(1)
    reg = {}
    for r in re.split(r'ROM_REGION\(', body)[1:]:
        rn = re.search(r'"([^"]+)"', r).group(1)
        reg[rn] = re.findall(r'ROM_LOAD(16_BYTE)?\( "([^"]+)",\s*(0x[0-9a-f]+),\s*(0x[0-9a-f]+),\s*CRC\(([0-9a-f]+)\)', r)
    rd = lambda f: z.read(by[f[4]])
    P = lambda f: f'name="{f[1]}" crc="{f[4]}"'
    img = bytearray()
    parts = []
    # 68000: even file -> high byte; JTFRAME 16-bit words are little endian in the download
    e, o = reg['maincpu'][0], reg['maincpu'][1]
    de, do = rd(e), rd(o)
    for k in range(len(de)): img += bytes([do[k], de[k]])
    parts += ['        <interleave output="16">', f'            <part {P(e)} map="10"/>', f'            <part {P(o)} map="01"/>', '        </interleave>']
    for f in reg['oki']: img += rd(f); parts.append(f'        <part {P(f)}/>')
    assert len(img) == 0x200000, hex(len(img))
    g = reg['gfx']
    if len(g) == 4:   # i13 i11 i09 i07, 16-bit interleaved halves
        d = [rd(f) for f in g]
        for k in range(0x80000): img += bytes([d[0][k], d[1][k], d[2][k], d[3][k]])
        parts += ['        <interleave output="32">'] + [f'            <part {P(f)} map="{m}"/>' for f, m in zip(g, ['0001', '0010', '0100', '1000'])] + ['        </interleave>']
    else:             # h12 h8: the same data as two 16-bit wide ROMs
        lo, hi = rd(g[0]), rd(g[1])
        for k in range(0, 0x100000, 2): img += lo[k:k+2] + hi[k:k+2]
        parts += ['        <interleave output="32">', f'            <part {P(g[0])} map="0021"/>', f'            <part {P(g[1])} map="2100"/>', '        </interleave>']
    assert len(img) == 0x400000
    m = reg['gaelco_ds5002fp:sram'][0]; img += rd(m); parts.append(f'        <part {P(m)}/>')
    open(f'{out}/{name}.rom', 'wb').write(img)
    open(f'{out}/{name}.md5', 'w').write(hashlib.md5(img).hexdigest())
    mra = f'''<!-- {title} on JTWRALLY, a personal MiSTer core for the Gaelco World Rally board (MAME wrally.cpp),
     built on JTFRAME by Jose Tejada (jotego). The ROM is assembled from your own MAME zip, unmodified
     (the DS5002FP protection CPU runs the dumped wrdallas.bin program). Requires jtwrally.rbf. -->
<misterromdescription>
    <name>{title} (JTWRALLY)</name>
    <setname>{name}</setname>
    <rotation>horizontal</rotation>
    <mameversion>0264</mameversion>
    <year>1993</year>
    <manufacturer>{man}</manufacturer>
    <players>2</players>
    <rbf>jtwrally</rbf>
    <joystick>8</joystick>
    <region>World</region>
    <rom index="0" zip="wrally.zip" md5="None">
{nl.join(parts)}
    </rom>
    <switches page_id="1" page_name="Switches" base="16" default="df,ff">
{nl.join('        ' + d for d in DIPS)}
    </switches>
    <buttons names="Accelerate,Gear Shift,Start,Coin,Core credits" default="A,B,Start,Select,-" count="2"/>
</misterromdescription>
'''
    open(f"{out}/mra/{title} (JTWRALLY).mra", 'w').write(mra)
    print(name, hashlib.md5(img).hexdigest())
