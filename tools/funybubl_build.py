#!/usr/bin/env python3
# funybubl_build.py outdir : JTFUNYBUBL images + MRAs for Funny Bubble (user's funybubl.zip)
import sys, os, zipfile, hashlib
S = '/tmp/claude-0/-home-claude/e1042311-2b93-5281-bddb-91ed22183aec/scratchpad'
SND, OKI, BA1, BA2, END = 0x40000, 0x50000, 0x100000, 0x300000, 0x500000
DIPS = ['<dip name="Coin A" bits="0,1,2" ids="Free Play,3C/1C,2C/1C,3C/2C,2C/3C,1C/3C,1C/2C,1C/1C"/>',
        '<dip name="Difficulty" bits="3,4,5" ids="-,Hard 4,Hard 3,Hard 2,Hard 1,Easy,Very Easy,Normal"/>',
        '<dip name="Demo Sounds" bits="6" ids="On,Off"/>', '<dip name="Nudity" bits="7" ids="Full,Semi"/>']
SPR = [('d.ug1', 'b7ebbc00'), ('e.ug2', '28afc396'), ('j.ug3', '9e8687cd'), ('k.ug4', '63f0e810')]
SND_F, OKI_F = ('p.su6', '33169d4d'), [('b.su12', 'a2d780f4'), ('c.su13', '1f7e9269')]
GAMES = [
    dict(set='funybubl', name='Funny Bubble', man='In Chang Electronic Co', main=('a.ub16', '4e799cdd'),
         til=[('f.ug13', '64d7163d'), ('g.uh13', '6891e2b8'), ('h.ug15', 'ca7f7528'), ('i.uh15', '23608ec6'),
              ('l.ug16', '0acf8143'), ('m.uh16', '55ed8d9c'), ('n.ug17', '52398b68'), ('o.uh17', '446e31b2')]),
    dict(set='funybublc', name='Funny Bubble (Comad version)', man='Comad', main=('2.ub16', 'd684c13f'),
         til=[('7.ug12', '87603d7b'), ('8.uh13', 'ab6031bd'), ('9.ug15', '0e8352ff'), ('10.uh15', 'df7dd356'),
              ('13.ug16', '9f57bdd5'), ('14.uh16', '2ac15ea3'), ('15.ug17', '9a5e66a6'), ('16.uh17', '218060b3')]),
]
out = sys.argv[1]; os.makedirs(f'{out}/mra', exist_ok=True)
nl = '\n'
P = lambda f: f'name="{f[0]}" crc="{f[1]}"'
z = zipfile.ZipFile(f'{S}/userzips/funybubl.zip'); by = {'%08x' % i.CRC: i for i in z.infolist()}
rd = lambda f: z.read(by[f[1]])
def ilv32(img, base, files, parts):
    d = [rd(f) for f in files]
    for k in range(len(d[0])):
        for q in range(4): img[base+4*k+q] = d[q][k]
    parts.append('        <interleave output="32">')
    for q, f in enumerate(files): parts.append(f'            <part {P(f)} map="{"".join("1" if 3-i==q else "0" for i in range(4))}"/>')
    parts.append('        </interleave>')
    return base + 4*len(d[0])
for g in GAMES:
    img = bytearray(END); parts = []
    m = rd(g['main']); img[0:len(m)] = m; parts.append(f'        <part {P(g["main"])}/>')
    s = rd(SND_F); img[SND:SND+len(s)] = s; parts.append(f'        <part {P(SND_F)}/>')
    parts.append(f'        <part repeat="0x{OKI-SND-len(s):x}"> 00</part>')
    pos = OKI
    for f in OKI_F:
        d = rd(f); img[pos:pos+len(d)] = d; pos += len(d); parts.append(f'        <part {P(f)}/>')
    img[pos:BA1] = b'\xff' * (BA1-pos); parts.append(f'        <part repeat="0x{BA1-pos:x}"> FF</part>')
    ilv32(img, BA1, SPR, parts)
    p = ilv32(img, BA2, g['til'][:4], parts)
    ilv32(img, p, g['til'][4:], parts)
    img = bytes(img)
    open(f'{out}/{g["set"]}.rom', 'wb').write(img); open(f'{out}/{g["set"]}.md5', 'w').write(hashlib.md5(img).hexdigest())
    mra = f'''<!-- {g["name"]} on JTFUNYBUBL, a personal MiSTer core for the Funny Bubble board (MAME funybubl.cpp "{g["set"]}"),
     built on JTFRAME by Jose Tejada (jotego). The ROM is assembled from your own MAME zip, unmodified. Requires jtfunybubl.rbf. -->
<misterromdescription>
    <name>{g["name"]} (JTFUNYBUBL)</name>
    <setname>{g["set"]}</setname>
    <rotation>horizontal</rotation>
    <mameversion>0264</mameversion>
    <year>1999</year>
    <manufacturer>{g["man"]}</manufacturer>
    <players>2</players>
    <rbf>jtfunybubl</rbf>
    <joystick>8</joystick>
    <region>World</region>
    <rom index="0" zip="funybubl.zip" md5="None">
{nl.join(parts)}
    </rom>
    <switches page_id="1" page_name="Switches" base="16" default="3f,ff">
{nl.join('        ' + d for d in DIPS)}
    </switches>
    <buttons names="Button 1,Start,Coin,Core credits" default="A,Start,Select,-" count="1"/>
</misterromdescription>
'''
    open(f'{out}/mra/{g["name"]} (JTFUNYBUBL).mra', 'w').write(mra)
    print(g['set'], hashlib.md5(img).hexdigest())
