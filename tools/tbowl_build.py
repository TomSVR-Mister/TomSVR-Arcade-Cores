#!/usr/bin/env python3
# tbowl_build.py outdir [rbf] : JTTBOWL images (.rom with header, for simulation) + MRAs from your own MAME zip
# tbowl.zip (tbowl tbowla tbowlp tbowlj), merged set.
# Layout after the 8-byte header (see tbowl/cfg/macros.def):
#   000000 main (128 kB MAME region)  020000 sub (128 kB)  040000 sound (32 kB)  050000 ADPCM (128 kB)
#   080000 bg tiles (512 kB)  100000 characters (64 kB)  180000 sprites (512 kB)  200000 bg tiles again (512 kB)
# Parts are found in the zip by CRC; the MRA uses the member names of the zip (clone files sit in sub folders).
import sys, os, zipfile
HERE = os.path.dirname(os.path.abspath(__file__))
ZIPS = os.environ.get('ZIPS', os.path.join(HERE, '..', 'roms'))

def dips(quarter):
    # Time (Players): value = index << 3, in MAME's order of values (0xf8 repeats 1:00)
    t = ['7:00', '6:00', '5:00', '4:30', '3:40', '3:20', '3:00', '2:50', '2:40', '2:30', '2:20', '2:10', '2:00',
         '1:55', '1:50', '1:45', '1:40', '1:35', '1:25', '1:20', '1:15', '1:10', '1:05', '1:00', '0:55', '0:50',
         '0:45', '0:40', '0:35', '0:30', '0:25', '1:00 (b)']
    return [
        '<dip name="Coinage" bits="0,2" ids="8C/1C,7C/1C,6C/1C,5C/1C,4C/1C,3C/1C,2C/1C,1C/1C"/>',
        f'<dip name="Time (Players)" bits="3,7" ids="{",".join(t)}"/>',
        '<dip name="Difficulty" bits="8,9" ids="Hardest,Hard,Easy,Normal"/>',
        '<dip name="Extra Time (Players)" bits="10,11" ids="0:30,0:20,0:10,None"/>',
        '<dip name="Timer Speed" bits="12,13" ids="Slowest,Slow,Fast,Normal"/>',
        '<dip name="Demo Sounds" bits="14" ids="Off,On"/>',
        '<dip name="Hi-Score Reset" bits="15" ids="Off,On"/>',
        f'<dip name="Time (Quarter)" bits="16,17" ids="{quarter}"/>',
        '<dip name="Bonus Frequency" bits="18,19" ids="Most,More,Normal,Least"/>',
    ]

MAIN_DATA = '133c5c11'
SUB = ['040c8138', '92c3cef5']
SND = '4370207b'
PCM = ['3aa24744', '1e9e5936']
CHR_W = ['f9cf60b9', 'a23f6c53']     # 14.13l / 15.15l (tbowl, tbowlp)
CHR_J = ['cf99d0bf', 'd69248cf']     # 6206b-14 / 6206b-15 (tbowla, tbowlj)
# bg tiles, LOAD16_BYTE pairs (even, odd) at 00000, 20000, 40000, 60000
BG = [('975ded4c', 'd139c397'), ('4ad72c16', '06bf07bb'), ('6389c719', 'b9615ffa'), ('7d0030f6', '9b4fa82e')]
SPR = [('97fba168', '71795604'), ('cf660ebc', '0684e188'), ('41b2a910', 'de16bc10'), ('70bb38a3', '1a2fb925')]
SPR_P = SPR[:3] + [('3c5654a9', '807af46a')]

Q_W = '8:00,5:00,3:00,4:00'
Q_J = '8:00,5:00,4:00,3:00'
GAMES = [
    dict(set='tbowl',  name='Tecmo Bowl (World, set 1)', region='World', main='db8a4f5d', chars=CHR_W, quarter=Q_W),
    dict(set='tbowla', name='Tecmo Bowl (World, set 2)', region='World', main='8c4260b1', chars=CHR_J, quarter=Q_W),
    dict(set='tbowlp', name='Tecmo Bowl (World, prototype)', region='World', main='db8a4f5d', chars=CHR_W,
         quarter=Q_W, sub=['1933a3f0', '7277c852'], snd='2158472d', spr=SPR_P),
    dict(set='tbowlj', name='Tecmo Bowl (Japan)', region='Japan', main='7ed3eff7', chars=CHR_J, quarter=Q_J),
]

out = sys.argv[1]; rbf = sys.argv[2] if len(sys.argv) > 2 else 'TomSVR_tbowl'
os.makedirs(f'{out}/mra', exist_ok=True)
xml = lambda s: s.replace('&', '&amp;').replace("'", '&apos;')
z = zipfile.ZipFile(os.path.join(ZIPS, 'tbowl.zip'))
by = {'%08x' % i.CRC: i for i in z.infolist()}

for g in GAMES:
    img = bytearray(); parts = []
    hdr = bytes(8)
    parts.append('<part>' + ' '.join('%02X' % b for b in hdr) + '</part>')
    def put(crc):
        i = by[crc]; img.extend(z.read(i))
        parts.append(f'<part name="{i.filename}" crc="{crc}"/>')
    def pad(to):
        if to > len(img):
            parts.append(f'<part repeat="0x{to-len(img):x}">FF</part>'); img.extend(b'\xff' * (to - len(img)))
        assert len(img) == to, (g['set'], hex(len(img)), hex(to))
    def inter16(even, odd):     # ROM_LOAD16_BYTE: even file = image byte 0
        e, o = z.read(by[even]), z.read(by[odd])
        for k in range(len(e)): img.extend((e[k], o[k]))
        parts.append('<interleave output="16">')
        parts.append(f'    <part name="{by[even].filename}" crc="{even}" map="01"/>')
        parts.append(f'    <part name="{by[odd].filename}" crc="{odd}" map="10"/>')
        parts.append('</interleave>')
    put(g['main']); pad(0x10000); put(MAIN_DATA)
    assert len(img) == 0x20000
    for c in g.get('sub', SUB): put(c)
    put(g.get('snd', SND)); pad(0x50000)
    for c in PCM: put(c)
    pad(0x80000)
    for e, o in BG: inter16(e, o)
    inter16(*g['chars']); pad(0x180000)
    for e, o in g.get('spr', SPR): inter16(e, o)
    for e, o in BG: inter16(e, o)
    assert len(img) == 0x280000
    open(f'{out}/{g["set"]}.rom', 'wb').write(hdr + img)
    nl = '\n        '
    d = '\n        '.join(dips(g['quarter']))
    mra = f'''<!-- {xml(g["name"])} on the TomSVR Tecmo Bowl core (MAME tecmo/tbowl.cpp), built on JTFRAME.
     Unofficial, MAME-based. The ROM is assembled from your own MAME zip, unmodified.
     Four players: coin = Select, start = Start, two buttons. OSD "Screens": both monitors side by side, or one. -->
<misterromdescription>
    <name>{xml(g["name"])} [TomSVR]</name>
    <setname>{g["set"]}</setname>
    <rotation>horizontal</rotation>
    <mameversion>0264</mameversion>
    <year>1987</year>
    <manufacturer>Tecmo</manufacturer>
    <players>4</players>
    <rbf>{rbf}</rbf>
    <joystick>8-way</joystick>
    <region>{g["region"]}</region>
    <rom index="0" zip="tbowl.zip" md5="None">
        {nl.join(parts)}
    </rom>
    <switches page_id="1" page_name="Switches" base="16" default="bf,ff,fb">
        {d}
    </switches>
    <buttons names="Button 1,Button 2,Start,Coin,Core credits" default="A,B,Start,Select,-" count="2"/>
</misterromdescription>
'''
    fn = g['name'].replace(':', ' -').replace('/', '-')
    open(f'{out}/mra/{fn} [TomSVR].mra', 'w').write(mra)
    print(f'{g["set"]:8} {len(img):#x}')
