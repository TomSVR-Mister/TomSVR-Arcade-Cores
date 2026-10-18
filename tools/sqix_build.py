#!/usr/bin/env python3
# sqix_build.py outdir : JTSQIX images + MRAs for Perestroika Girls (user's perestro.zip)
import sys, os, zipfile, hashlib
S = '/tmp/claude-0/-home-claude/e1042311-2b93-5281-bddb-91ed22183aec/scratchpad'
z = zipfile.ZipFile(f'{S}/userzips/perestro.zip'); by = {'%08x' % i.CRC: i for i in z.infolist()}
rd = lambda c: z.read(by[c])
SETS = {
  'perestro':  dict(title='Perestroika Girls', man='Promat', year='1994',
                    roms=[('rom1.bin', '0cbf96c1'), ('rom4.bin', 'c56122a8'), ('rom2.bin', '36f93701'), ('rom3a.bin', '7a2a563f')]),
  'perestrof': dict(title='Perestroika Girls (Fuuki license)', man='Promat (Fuuki license)', year='1993',
                    roms=[('rom1.bin', '0cbf96c1'), ('rom4.bin', 'c56122a8'), ('rom2.bin', '36f93701'), ('rom3.bin', '00c91d5a')]),
}
DIPS = [
    '<dip name="Cabinet" bits="0" ids="Upright,Cocktail"/>',
    '<dip name="Freeze" bits="2" ids="On,Off"/>',
    '<dip name="Allow Continue" bits="3" ids="Yes,No"/>',
    '<dip name="Coin A" bits="4,5" ids="2C/3C,2C/1C,1C/2C,1C/1C"/>',
    '<dip name="Coin B" bits="6,7" ids="2C/3C,2C/1C,1C/2C,1C/1C"/>',
    '<dip name="Difficulty" bits="8,9" ids="Hardest,Hard,Easy,Normal"/>',
    '<dip name="Bonus Life" bits="10,11" ids="None,50000 100000,20000 50000,30000 100000"/>',
    '<dip name="Lives" bits="12,13" ids="5,4,2,3"/>',
    '<dip name="Fill Area" bits="14,15" ids="85%,80%,70%,75%"/>',
]
out = sys.argv[1]; os.makedirs(f'{out}/mra', exist_ok=True)
for name, a in SETS.items():
    img = b''.join(rd(c) for _, c in a['roms'])
    assert len(img) == 0x60000
    open(f'{out}/{name}.rom', 'wb').write(img)
    open(f'{out}/{name}.md5', 'w').write(hashlib.md5(img).hexdigest())
    parts = '\n'.join(f'        <part name="{n}" crc="{c}"/>' for n, c in a['roms'])
    nl = '\n'
    mra = f'''<!-- {a['title']} on JTSQIX, a personal MiSTer core for the Super Qix board without MCU (MAME superqix.cpp "sqix_nomcu"),
     built on JTFRAME by Jose Tejada (jotego). The ROM is assembled from your own MAME zip, unmodified
     (the program and graphics byte shuffle of this bootleg is undone in the core). Requires jtsqix.rbf. -->
<misterromdescription>
    <name>{a['title']} (JTSQIX)</name>
    <setname>{name}</setname>
    <rotation>vertical (cw)</rotation>
    <mameversion>0264</mameversion>
    <year>{a['year']}</year>
    <manufacturer>{a['man']}</manufacturer>
    <players>2</players>
    <rbf>jtsqix</rbf>
    <joystick>4</joystick>
    <region>World</region>
    <rom index="0" zip="perestro.zip" md5="None">
{parts}
    </rom>
    <rom index="1">
        <part>01 80</part>
    </rom>
    <switches page_id="1" page_name="Switches" base="16" default="f6,ff">
{nl.join('        ' + d for d in DIPS)}
    </switches>
    <buttons names="Button 1,Button 2,Start,Coin,Core credits" default="A,B,Start,Select,-" count="2"/>
</misterromdescription>
'''
    open(f"{out}/mra/{a['title']} (JTSQIX).mra", 'w').write(mra)
    print(name, hashlib.md5(img).hexdigest())
