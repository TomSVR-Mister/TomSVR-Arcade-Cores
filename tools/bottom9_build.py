#!/usr/bin/env python3
# bottom9_build.py outdir [rbf] : JTBOTTOM9 images (.rom, for simulation) + MRAs from your own MAME bottom9.zip
# (merged set: bottom9, bottom9n, mstadium). Layout (see bottom9/cfg/macros.def):
#   000000 main (0x20000)  020000 Z80 (0x8000)  028000 007232 #1  068000 007232 #2  0A8000 051316 (4 bpp)
#   0C8000 052109 tiles (MAME byte order)  148000 051960 sprites (32-bit words, bytes reversed)
import sys, os, zipfile, hashlib
HERE = os.path.dirname(os.path.abspath(__file__))
ZIPS = os.environ.get('ZIPS', os.path.join(HERE, '..', 'roms'))
END = 0x248000

COIN = '4C/5C,4C/3C,4C/1C,3C/4C,3C/2C,3C/1C,2C/5C,2C/3C,2C/1C,1C/7C,1C/6C,1C/5C,1C/4C,1C/3C,1C/2C,1C/1C'
DIPS_COMMON = [f'<dip name="Coin A" bits="0,3" ids="{COIN}"/>',
               f'<dip name="Coin B" bits="4,7" ids="{COIN}"/>']
DIPS_TAIL = ['<dip name="Flip Screen" bits="16" ids="On,Off"/>',
             '<dip name="Service Mode" bits="18" ids="On,Off"/>',
             '<dip name="Fielder Control" bits="19" ids="Auto,Normal"/>']
B9_DIPS = ['<dip name="Play Time" bits="8,10" ids="2:10,2:00,1:50,1:40,1:30,1:20,1:10,1:00"/>',
           '<dip name="Bonus Time" bits="11,12" ids="40 sec,30 sec,20 sec,None"/>',
           '<dip name="Difficulty" bits="13,14" ids="Very Difficult,Difficult,Normal,Easy"/>',
           '<dip name="Demo Sounds" bits="15" ids="On,Off"/>']
MS_DIPS = ['<dip name="Play Inning" bits="8,9" ids="4,3,2,1"/>',
           '<dip name="Play Inning Time" bits="10,11" ids="12 min,10 min,8 min,6 min"/>',
           '<dip name="Difficulty" bits="13,14" ids="Very Difficult,Difficult,Normal,Easy"/>',
           '<dip name="Demo Sounds" bits="15" ids="On,Off"/>']
# defaults (MAME): DSW1 ff, DSW2 4c (b9) / 59 (ms: inning 3, 8 min, unknown off, normal, demo on), DSW3 f
GAMES = [
    dict(set='bottom9',  name='Bottom of the Ninth (version T)', region='World', year='1989',
         main=[('891n03.k17', '8b083ff3'), ('891-t02.k15', '2c10ced2')], snd=('891j01.g8', '31b0a0a8'),
         dips=B9_DIPS, dsw2='4c', buttons=2),
    dict(set='bottom9n', name='Bottom of the Ninth (version N)', region='World', year='1989',
         main=[('891n03.k17', '8b083ff3'), ('891n02.k15', 'd44d9ed4')], snd=('891j01.g8', '31b0a0a8'),
         dips=B9_DIPS, dsw2='4c', buttons=2),
    dict(set='mstadium', name='Main Stadium (Japan)', region='Japan', year='1989',
         main=[('891-403.k17', '1c00c4e8'), ('891-402.k15', 'b850bbce')], snd=('891w01.g8', 'edec565a'),
         dips=MS_DIPS, dsw2='59', buttons=3),
]
PCM1 = [('891e08a', 'cef667bf'), ('891e08b', 'f7c14a7a'), ('891e08c', '756b7f3c'), ('891e08d', 'cd0d7305')]
PCM2 = [('891e04a', 'daebbc74'), ('891e04b', '5ffb9ad1'), ('891e04c', '2dbbf16b'), ('891e04d', '8b0cd2cc')]
ROZ  = [('891e07a', 'b8d8b939'), ('891e07b', '83b2f92d')]
# 052109: ROM_LOAD32_BYTE, MAME byte 0..3 of each word; two halves (0x00000, 0x40000)
TILES = [[('891e10c', '209b0431'), ('891e10a', '8020a9e8'), ('891e09c', '9dcaefbf'), ('891e09a', '56b0ead9')],
         [('891e10d', '16d5fd7a'), ('891e10b', '30121cc0'), ('891e09d', '4e1335e6'), ('891e09b', 'b6f914fb')]]
SPRITES = [[('891e06e', '0b04db1c'), ('891e06a', '5ee37327'), ('891e05e', 'b356e729'), ('891e05a', 'bfd5487e')],
           [('891e06f', 'f9ada524'), ('891e06b', '2295dfaa'), ('891e05f', 'ecdd11c5'), ('891e05b', 'aba18d24')],
           [('891e06g', '04abf78f'), ('891e06c', 'dbdb0d55'), ('891e05g', 'c315f9ae'), ('891e05c', '21fcbc6f')],
           [('891e06h', '5d5ded8c'), ('891e06d', 'f9ecbd71'), ('891e05h', 'b0aba53b'), ('891e05d', 'f6d3f886')]]

out = sys.argv[1]; rbf = sys.argv[2] if len(sys.argv) > 2 else 'TomSVR_bottom9'
os.makedirs(f'{out}/mra', exist_ok=True)
nl = '\n'
xml = lambda s: s.replace('&', '&amp;')
P = lambda f, extra='': f'<part name="{f[0]}" crc="{f[1]}"{extra}/>'
z = zipfile.ZipFile(os.path.join(ZIPS, 'bottom9.zip'))
by = {'%08x' % i.CRC: i for i in z.infolist()}
rd = lambda f: z.read(by[f[1]])

for g in GAMES:
    img = bytearray(); parts = []
    h = hashlib.md5()  # MiSTer hashes the part data in MRA order, not the assembled image
    def put(f):
        img.extend(rd(f)); h.update(rd(f)); parts.append(P(f))
    def word32(group, rev):
        # MRA map digits: output bytes 3..0 from left to right, value = 1-based byte of the part
        data = [rd(f) for f in group]
        for d in data: h.update(d)
        for k in range(len(data[0])):
            w = [d[k] for d in data]
            img.extend(reversed(w) if rev else w)
        parts.append('<interleave output="32">')
        for i, f in enumerate(group):
            pos = 3 - i if rev else i
            m = ''.join('1' if 3 - c == pos else '0' for c in range(4))
            parts.append('    ' + P(f, f' map="{m}"'))
        parts.append('</interleave>')
    for f in g['main']: put(f)
    put(g['snd'])
    for f in PCM1 + PCM2 + ROZ: put(f)
    for grp in TILES: word32(grp, False)
    for grp in SPRITES: word32(grp, True)
    assert len(img) == END, hex(len(img))
    open(f'{out}/{g["set"]}.rom', 'wb').write(img)
    md5 = h.hexdigest()
    # the core always has 3 button slots before Start and Coin; an unused slot still needs a name: MiSTer drops '-' names and the rest shift
    btn, dflt = ('Button 1,Button 2,Button 3', 'A,B,X') if g['buttons'] == 3 else ('Button 1,Button 2,Unused', 'A,B,-')
    mra = f'''<!-- {g["name"]} on the TomSVR Bottom of the Ninth core (MAME bottom9.cpp, Konami GX891), built on JTFRAME
     and jotego's Konami chip models. Unofficial, MAME-based. The ROM is assembled from your own MAME zip, unmodified. -->
<misterromdescription>
    <name>{xml(g["name"])} [TomSVR]</name>
    <setname>{g["set"]}</setname>
    <rotation>horizontal</rotation>
    <mameversion>0264</mameversion>
    <year>{g["year"]}</year>
    <manufacturer>Konami</manufacturer>
    <players>2</players>
    <rbf>{rbf}</rbf>
    <joystick>8-way</joystick>
    <region>{g["region"]}</region>
    <rom index="0" zip="bottom9.zip" md5="{md5}">
{nl.join('        ' + p for p in parts)}
    </rom>
    <switches page_id="1" page_name="Switches" base="16" default="ff,{g["dsw2"]},0f">
{nl.join('        ' + d for d in DIPS_COMMON + g["dips"] + DIPS_TAIL)}
    </switches>
    <buttons names="{btn},Start,Coin,Core credits" default="{dflt},Start,Select,-" count="3"/>
</misterromdescription>
'''
    open(f'{out}/mra/{g["name"]} [TomSVR].mra', 'w').write(mra)
    open(f'{out}/{g["set"]}.md5', 'w').write(md5)
    print(g['set'], md5)
