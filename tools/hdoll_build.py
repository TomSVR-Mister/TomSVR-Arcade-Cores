#!/usr/bin/env python3
# hdoll_build.py outdir : JTHDOLL image + MRA for Honey Doll (user's honeydol.zip)
import sys, os, zipfile, hashlib
S = '/tmp/claude-0/-home-claude/e1042311-2b93-5281-bddb-91ed22183aec/scratchpad'
z = zipfile.ZipFile(f'{S}/userzips/honeydol.zip'); by = {'%08x' % i.CRC: i for i in z.infolist()}
rd = lambda f: z.read(by[f[1]])
EVEN, ODD = ('d-17.ui12', 'cac44154'), ('d-16.uh12', 'cee1a2e3')
SND, OKI, O4 = ('d-12.uh15', '386f1b63'), ('d-11.u14', 'f3ee4861'), ('d-13.1', 'ff6a57fb')
O8 = [(('d-14.5', '2178996f'), ('d-18.9', '0210507a')), (('d-15.6', '6629239e'), ('d-19.10', 'd27375d5'))]
SNDA, OKIA, BA1, BA2, END = 0x40000, 0x50000, 0x100000, 0x200000, 0x400000
img = bytearray(END)
e, o = rd(EVEN), rd(ODD)
for k in range(len(e)): img[2*k+1] = e[k]; img[2*k] = o[k]
s = rd(SND); img[SNDA:SNDA+len(s)] = s
p = rd(OKI); img[OKIA:OKIA+len(p)] = p; img[OKIA+len(p):BA1] = b'\xff' * (BA1-OKIA-len(p))
g = rd(O4); img[BA1:BA1+len(g)] = g; img[BA1+len(g):BA2] = b'\xff' * (BA2-BA1-len(g))
pos = BA2
for a, b in O8:
    x, y = rd(a), rd(b)
    for k in range(len(x)): img[pos+2*k] = x[k]; img[pos+2*k+1] = y[k]
    pos += 2*len(x)
out = sys.argv[1]; os.makedirs(f'{out}/mra', exist_ok=True)
open(f'{out}/honeydol.rom', 'wb').write(img); open(f'{out}/honeydol.md5', 'w').write(hashlib.md5(img).hexdigest())
P = lambda f: f'name="{f[0]}" crc="{f[1]}"'
parts = [ '        <interleave output="16">', f'            <part {P(EVEN)} map="10"/>', f'            <part {P(ODD)} map="01"/>', '        </interleave>',
          f'        <part repeat="0x{SNDA-2*len(e):x}"> 00</part>', f'        <part {P(SND)}/>', f'        <part repeat="0x{OKIA-SNDA-len(s):x}"> 00</part>',
          f'        <part {P(OKI)}/>', f'        <part repeat="0x{BA1-OKIA-len(p):x}"> FF</part>', f'        <part {P(O4)}/>',
          f'        <part repeat="0x{BA2-BA1-len(g):x}"> FF</part>']
for a, b in O8:
    parts += ['        <interleave output="16">', f'            <part {P(a)} map="01"/>', f'            <part {P(b)} map="10"/>', '        </interleave>']
DIPS = ['<dip name="Coinage" bits="0,1" ids="3C/1C,2C/1C,1C/2C,1C/1C"/>', '<dip name="Show Girls" bits="2" ids="Off,On"/>',
        '<dip name="Demo Sounds" bits="4" ids="Off,On"/>', '<dip name="Level Select" bits="6" ids="On,Off"/>',
        '<dip name="Slide Show On Boot-up" bits="7" ids="On,Off"/>', '<dip name="Difficulty" bits="8,9" ids="Hardest,Harder,Hard,Normal"/>',
        '<dip name="Timer Speed" bits="10,11" ids="Fastest,Faster,Fast,Normal"/>', '<dip name="Lives" bits="12,13" ids="1,2,3,5"/>',
        '<dip name="Max Vs Round" bits="15" ids="1,3"/>']
nl = '\n'
mra = f'''<!-- Honey Doll on JTHDOLL, a personal MiSTer core for the Barko Honey Doll board (MAME snowbros.cpp "honeydol"),
     built on JTFRAME by Jose Tejada (jotego). The ROM is assembled from your own MAME zip, unmodified. Requires jthdoll.rbf. -->
<misterromdescription>
    <name>Honey Doll (JTHDOLL)</name>
    <setname>honeydol</setname>
    <rotation>horizontal</rotation>
    <mameversion>0264</mameversion>
    <year>1995</year>
    <manufacturer>Barko Corp.</manufacturer>
    <players>2</players>
    <rbf>jthdoll</rbf>
    <joystick>8</joystick>
    <region>World</region>
    <rom index="0" zip="honeydol.zip" md5="None">
{nl.join(parts)}
    </rom>
    <rom index="1">
        <part>00 80</part>
    </rom>
    <switches page_id="1" page_name="Switches" base="16" default="ff,ef">
{nl.join('        ' + d for d in DIPS)}
    </switches>
    <buttons names="Button 1,Button 2,Button 3,Start,Coin,Core credits" default="A,B,X,Start,Select,-" count="3"/>
</misterromdescription>
'''
open(f'{out}/mra/Honey Doll (JTHDOLL).mra', 'w').write(mra); print(hashlib.md5(img).hexdigest())
