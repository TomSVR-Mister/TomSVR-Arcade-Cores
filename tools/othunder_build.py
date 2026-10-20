#!/usr/bin/env python3
# othunder_build.py outdir : JTOTHUNDER images + MRAs for Operation Thunderbolt (user's merged othunder.zip)
# Image: 68000 program 0 (512 kB, 16-bit big endian words), Z80 0x80000, YM2610 ADPCM-A 0x90000,
# ADPCM-B 0x110000, sprite planes 2-3 0x200000, TC0100SCN tiles 0x300000, sprite map 0x380000, sprite planes 0-1
# 0x400000 (one 16-bit plane word per ROM, 32-bit words), 93C46 default contents 0x600000 (little endian words).
import sys, os, zipfile, hashlib
S = '/tmp/claude-0/-home-claude/183009bc-02e0-578a-b0ba-00b6083aaf64/scratchpad'
DIPS = [
    '<dip name="Allow Continue" bits="1" ids="No,Yes"/>',
    '<dip name="Service Mode" bits="2" ids="On,Off"/>',
    '<dip name="Demo Sounds" bits="3" ids="Off,On"/>',
    '<dip name="Coin A" bits="4,5" ids="4C/1C,3C/1C,2C/1C,1C/1C"/>',
    '<dip name="Coin B" bits="6,7" ids="1C/6C,1C/4C,1C/3C,1C/2C"/>',
    '<dip name="Difficulty" bits="8,9" ids="Hardest,Hard,Easy,Medium"/>',
    '<dip name="Magazines/Rockets" bits="10,11" ids="8/6,7/5,6/4,5/3"/>',
    '<dip name="Bullets per Magazine" bits="12,13" ids="30,35,50,40"/>',
    '<dip name="Language" bits="15" ids="English,Japanese"/>',
]
SETS = {
    'othunder':    ('Operation Thunderbolt (World, rev 1)', 'b67-20-1.ic63',             'b67-23-1.ic64',             'World'),
    'othundero':   ('Operation Thunderbolt (World)',        'othunderj/b67-20.ic63',     'othundero/b67-23.ic64',     'World'),
    'othunderu':   ('Operation Thunderbolt (US, rev 1)',    'b67-20-1.ic63',             'othunderu/b67-22-1.ic64',   'USA'),
    'othunderua':  ('Operation Thunderbolt (US)',           'othunderj/b67-20.ic63',     'othunderua/b67-22.ic64',    'USA'),
    'othunderj':   ('Operation Thunderbolt (Japan)',        'othunderj/b67-20.ic63',     'othunderj/b67-21.ic64',     'Japan'),
    'othunderjsc': ('Operation Thunderbolt (Japan, SC)',    'othunderjsc/b67-24.ic63',   'othunderjsc/b67-25.ic64',   'Japan'),
}
out = sys.argv[1]; os.makedirs(f'{out}/mra', exist_ok=True)
z = zipfile.ZipFile(f'{S}/userzips/othunder.zip')
rd = lambda n: z.read(n)
crc = lambda n: '%08x' % z.getinfo(n).CRC
P = lambda n, extra='': f'<part name="{n.split("/")[-1]}" crc="{crc(n)}"{extra}/>'
nl = '\n'

def il16(e, o):    # 68000: big endian words, even ROM in the upper byte
    a, b = rd(e), rd(o)
    return bytes(x for k in range(len(a)) for x in (b[k], a[k]))

for name, (title, ev, od, region) in SETS.items():
    img = il16(ev, od) + il16('b67-14.ic61', 'b67-15.ic62')
    img += rd('b67-13.ic40') + rd('b67-08.ic67') + rd('b67-07.ic44')
    img += bytes([0xff]) * (0x200000 - len(img))
    pl = [rd(f'b67-0{i}.ic{i}') for i in range(1, 5)]
    pair = lambda a, b: bytes(x for k in range(0, len(a), 2) for x in a[k:k+2] + b[k:k+2])
    img += pair(pl[2], pl[3])
    img += bytes([0xff]) * (0x300000 - len(img))
    img += rd('b67-06.ic66') + rd('b67-05.ic43')
    img += bytes([0xff]) * (0x400000 - len(img))
    img += pair(pl[0], pl[1])
    img += bytes([0xff]) * (0x600000 - len(img))
    e = rd('93c46_eeprom-othunder.ic86')
    img += bytes(x for k in range(0, len(e), 2) for x in (e[k+1], e[k]))
    assert len(img) == 0x600080, hex(len(img))
    parts = ['<interleave output="16">', '    ' + P(ev, ' map="10"'), '    ' + P(od, ' map="01"'), '</interleave>',
             '<interleave output="16">', '    ' + P('b67-14.ic61', ' map="10"'), '    ' + P('b67-15.ic62', ' map="01"'), '</interleave>',
             P('b67-13.ic40'), P('b67-08.ic67'), P('b67-07.ic44'), '<part repeat="0x70000">FF</part>',
             '<interleave output="32">', '    ' + P('b67-03.ic3', ' map="0021"'), '    ' + P('b67-04.ic4', ' map="2100"'), '</interleave>',
             P('b67-06.ic66'), P('b67-05.ic43'),
             '<interleave output="32">', '    ' + P('b67-01.ic1', ' map="0021"'), '    ' + P('b67-02.ic2', ' map="2100"'), '</interleave>',
             '<part repeat="0x100000">FF</part>',
             '<interleave output="16">', '    ' + P('93c46_eeprom-othunder.ic86', ' map="12"'), '</interleave>']
    open(f'{out}/{name}.rom', 'wb').write(img)
    md5 = hashlib.md5(img).hexdigest()
    mra = f'''<!-- {title} on JTOTHUNDER, a personal MiSTer core for Taito's Operation Thunderbolt board (MAME othunder.cpp),
     built on JTFRAME and jotego's CPU and sound models. The ROM is assembled from your own MAME zip, unmodified.
     Controls: aim with a mouse, light gun or the left analog stick; button 1 fires, button 2 launches a rocket.
     The picture is mirrored like the original cabinet, which is viewed through a mirror. Requires jtothunder.rbf. -->
<misterromdescription>
    <name>{title} (JTOTHUNDER)</name>
    <setname>{name}</setname>
    <rotation>horizontal</rotation>
    <mameversion>0264</mameversion>
    <year>1988</year>
    <manufacturer>Taito</manufacturer>
    <players>2</players>
    <rbf>jtothunder</rbf>
    <joystick>lightgun</joystick>
    <region>{region}</region>
    <rom index="0" zip="othunder.zip" md5="None">
{nl.join('        ' + p for p in parts)}
    </rom>
    <rom index="1">
        <part>02 00</part>
    </rom>
    <nvram index="2" size="128"/>
    <switches page_id="1" page_name="Switches" base="16" default="ff,7f">
{nl.join('        ' + d for d in DIPS)}
    </switches>
    <buttons names="Fire,Rocket,Start,Coin,Core credits" default="A,B,Start,Select,-" count="2"/>
</misterromdescription>
'''
    open(f"{out}/mra/{title} (JTOTHUNDER).mra", 'w').write(mra)
    open(f"{out}/{name}.md5", "w").write(md5)
    print(name, md5)
