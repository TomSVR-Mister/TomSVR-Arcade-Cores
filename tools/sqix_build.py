#!/usr/bin/env python3
# sqix_build.py outdir : JTSQIX images + MRAs for Super Qix (user's sqix.zip) and Perestroika Girls (perestro.zip)
# Image after the 4-byte header: program 0 (0x20000), chars 0x20000 (0x10000), tiles 0x30000 (0x20000),
# sprites 0x50000 (0x10000), i8751 program 0x60000 (0x1000, MCU sets only).
# Header byte 0: bit 0 Perestroika byte shuffle, bit 1 i8751 fitted.
import sys, os, zipfile, hashlib
S = '/tmp/claude-0/-home-claude/183009bc-02e0-578a-b0ba-00b6083aaf64/scratchpad'
P8, S8 = ('taito_sq-iu3__lh231041__sharp_japan__8709_d.p8', 'b8d0c493'), ('b03__04.s8', 'f815ef45')
H3, T8 = ('b03__02.h3', '9c23cb64'), ('b03__05.t8', 'df326540')
MCU = ('b03__03.l2', 'f0c3af2b')
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
SQ = dict(zip='sqix.zip', man='Kaneko / Taito', year='1987', chars=[S8, S8], tiles=P8)
SETS = {
  'sqix':   dict(SQ, title='Super Qix (World-Japan, V1.2)', hdr=2, prog=[('b03__01-2.ef3', '5ded636b'), H3], spr=T8, mcu=MCU),
  'sqixr1': dict(SQ, title='Super Qix (World-Japan, V1.1)', hdr=2, prog=[('b03__01-1.ef3', 'ad614117'), H3], spr=T8, mcu=MCU),
  'sqixr0': dict(SQ, title='Super Qix (World-Japan, V1.0)', hdr=2, prog=[('b03__01.ef3', '0888b7de'), H3], spr=T8, mcu=MCU),
  'sqixu':  dict(SQ, title='Super Qix (US)', man='Kaneko / Taito (Romstar license)', hdr=2,
                 prog=[('b03__06.ef3', '4f59f7af'), ('b03__07.h3', '4c417d4a')], spr=('b03__09.t8', '69d2a84a'), mcu=('b03__08.l2', '7c338c0f')),
  'sqixb2': dict(SQ, title='Super Qix (bootleg, No MCU)', man='bootleg', hdr=0, prog=[('cpu.2', '682e28e3'), H3], spr=T8, mcu=None),
  'perestro':  dict(zip='perestro.zip', title='Perestroika Girls', man='Promat', year='1994', hdr=1, prog=[('rom1.bin', '0cbf96c1')],
                    chars=[('rom4.bin', 'c56122a8')], tiles=('rom2.bin', '36f93701'), spr=('rom3a.bin', '7a2a563f'), mcu=None),
  'perestrof': dict(zip='perestro.zip', title='Perestroika Girls (Fuuki license)', man='Promat (Fuuki license)', year='1993', hdr=1,
                    prog=[('rom1.bin', '0cbf96c1')], chars=[('rom4.bin', 'c56122a8')], tiles=('rom2.bin', '36f93701'),
                    spr=('rom3.bin', '00c91d5a'), mcu=None),
}
out = sys.argv[1]; os.makedirs(f'{out}/mra', exist_ok=True)
nl = '\n'
for name, a in SETS.items():
    z = zipfile.ZipFile(f'{S}/userzips/{a["zip"]}'); by = {'%08x' % i.CRC: i for i in z.infolist()}
    rd = lambda f: z.read(by[f[1]])
    P = lambda f: f'        <part name="{f[0]}" crc="{f[1]}"/>'
    parts, img = [f'        <part>{a["hdr"]:02X} 00 00 00</part>'], bytearray()
    def add(f): global img; img += rd(f); parts.append(P(f))
    def pad(n, v=0):
        global img
        if n: img += bytes([v]) * n; parts.append(f'        <part repeat="0x{n:x}"> {v:02X}</part>')
    add(a['prog'][0])
    if len(a['prog']) > 1: pad(0x10000 - len(img)); add(a['prog'][1])
    pad(0x20000 - len(img))
    for f in a['chars']: add(f)
    add(a['tiles']); add(a['spr'])
    assert len(img) == 0x60000, hex(len(img))
    if a['mcu']: add(a['mcu'])
    full = bytes([a['hdr'], 0, 0, 0]) + img
    open(f'{out}/{name}.rom', 'wb').write(full)
    open(f'{out}/{name}.md5', 'w').write(hashlib.md5(full).hexdigest())
    note = ('the i8751 MCU runs its own dumped program' if a['mcu'] else
            'the program and graphics byte shuffle of this bootleg is undone in the core' if a['hdr'] & 1 else
            'this bootleg runs without the MCU')
    mra = f'''<!-- {a['title']} on JTSQIX, a personal MiSTer core for the Super Qix board (MAME superqix.cpp),
     built on JTFRAME by Jose Tejada (jotego). The ROM is assembled from your own MAME zip, unmodified
     ({note}). Requires jtsqix.rbf. -->
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
    <rom index="0" zip="{a['zip']}" md5="None">
{nl.join(parts)}
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
    print(name, hashlib.md5(full).hexdigest())
