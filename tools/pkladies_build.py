#!/usr/bin/env python3
# pkladies_build.py outdir : JTPKLADIES (JTPANG fork) images + MRAs for Poker Ladies (user's pkladies.zip)
import sys, os, zipfile, hashlib
S = '/tmp/claude-0/-home-claude/e1042311-2b93-5281-bddb-91ed22183aec/scratchpad'
BA1, BA2, BA3, END = 0x80000, 0x100000, 0x300000, 0x340000
HDR = bytes.fromhex('76 54 32 10 01 23 45 67 AA 55 A5 00 00 00 00 04')   # Kabuki keys (as JTPANG), byte 15 = key matrix input
CHR = [(('pko-001.8h', '1ead5d9b'), ('pko-003.8j', '339ab4e6')), (('pko-002.9h', '1cf02586'), ('pko-004.9j', '09ccb442'))]
SPR = (('pko-chr1.2j', '31ce33cd'), ('pko-chr2.3j', 'ad7e055f'))
OKI = [('pko-voi1.2d', '07e0f531'), ('pko-voi2.3d', '18398bf6')]
GAMES = [
    dict(set='pkladies', name='Poker Ladies', man='Mitchell', main=[('pko-prg1.14f', '86585a94'), ('pko-prg2.15f', '86cbe82d')]),
    dict(set='pkladiesl', name='Poker Ladies (Leprechaun ver. 510)', man='Leprechaun', main=[('pk05.14f', 'ea1740a6'), ('pk06.15f', '3078ff5e')]),
    dict(set='pkladiesla', name='Poker Ladies (Leprechaun ver. 401)', man='Leprechaun', main=[('pk05.14f', 'fa18e16a'), ('pk06.15f', 'a2fb7646')]),
]
out = sys.argv[1]; os.makedirs(f'{out}/mra', exist_ok=True)
z = zipfile.ZipFile(f'{S}/userzips/pkladies.zip'); by = {'%08x' % i.CRC: i for i in z.infolist()}
rd = lambda f: z.read(by[f[1]])
P = lambda f: f'name="{f[0]}" crc="{f[1]}"'
nl = '\n'
for g in GAMES:
    img = bytearray(b'\xff' * END); parts = [f'        <part> {HDR.hex(" ").upper()} </part>']
    pos = 0
    for f in g['main']:
        d = rd(f); img[pos:pos+len(d)] = d; pos += len(d); parts.append(f'        <part {P(f)}/>')
    parts.append(f'        <part repeat="0x{BA1-pos:x}"> FF</part>')
    pos = BA1
    for f in OKI:
        d = rd(f); img[pos:pos+len(d)] = d; pos += len(d); parts.append(f'        <part {P(f)}/>')
    parts.append(f'        <part repeat="0x{BA2-pos:x}"> FF</part>')
    pos = BA2
    for a, b in CHR + [SPR]:
        x, y = rd(a), rd(b)
        for k in range(len(x)): img[pos+2*k] = x[k]; img[pos+2*k+1] = y[k]
        pos += 2*len(x)
        parts += ['        <interleave output="16">', f'            <part {P(a)} map="01"/>', f'            <part {P(b)} map="10"/>', '        </interleave>']
    full = HDR + bytes(img)
    open(f'{out}/{g["set"]}.rom', 'wb').write(full); open(f'{out}/{g["set"]}.md5', 'w').write(hashlib.md5(full).hexdigest())
    mra = f'''<!-- {g["name"]} on JTPKLADIES, a personal fork of Jose Tejada's (jotego) JTPANG core with the Poker Ladies
     key matrix wired to 8 buttons. Built on JTFRAME. The ROM is assembled from your own MAME zip, unmodified.
     Requires jtpkladies.rbf. Please support jotego: https://patreon.com/jotego -->
<misterromdescription>
    <name>{g["name"]} (JTPKLADIES)</name>
    <setname>{g["set"]}</setname>
    <rotation>horizontal</rotation>
    <mameversion>0264</mameversion>
    <year>1989</year>
    <manufacturer>{g["man"]}</manufacturer>
    <players>1</players>
    <rbf>jtpkladies</rbf>
    <joystick>8</joystick>
    <region>World</region>
    <rom index="0" zip="pkladies.zip" md5="None">
{nl.join(parts)}
    </rom>
    <nvram index="2" size="128"/>
    <rom index="1">
        <part>00 80</part>
    </rom>
    <buttons names="Deal,Cancel,Flip,Hold A,Hold B,Hold C,Hold D,Hold E,Start,Coin,Core credits" default="A,B,X,Y,L,R,-,-,Start,Select,-" count="8"/>
</misterromdescription>
'''
    open(f'{out}/mra/{g["name"]} (JTPKLADIES).mra', 'w').write(mra)
    print(g['set'], hashlib.md5(full).hexdigest(), hex(len(full)))
