#!/usr/bin/env python3
# pipedrm_build.py outdir [rbf] : JTPIPEDRM images (.rom, for simulation) + MRAs from the user's own MAME zips
# (pipedrm.zip, hatris.zip, merged sets). Layout (after the 8-byte header, see pipedrm/cfg/macros.def):
#   000000 maincpu (0x20000)  020000 sub (0x20000)  100000 gfx1  200000 gfx2  300000 gfx3 (sprites)
#   380000 ADPCM-A / YM2608 rhythm ROM  400000 ADPCM-B
import sys, os, zipfile, hashlib
HERE = os.path.dirname(os.path.abspath(__file__))
ZIPS = os.environ.get('ZIPS', os.path.join(HERE, '..', 'roms'))   # folder with your own pipedrm.zip
HDR, SND, BA1, BA2, BA3, PCMA, PCMB, END = 8, 0x20000, 0x100000, 0x200000, 0x300000, 0x380000, 0x400000, 0x480000

COIN = '2C/3C,4C/5C,5C/6C,4C/3C,6C/4C,2C/3C,5C/1C,4C/1C,3C/1C,2C/1C,1C/6C,1C/5C,1C/4C,1C/3C,1C/2C,1C/1C'
PD_DIPS = [f'<dip name="Coin A" bits="0,3" ids="{COIN}"/>', f'<dip name="Coin B" bits="4,7" ids="{COIN}"/>',
           '<dip name="Difficulty" bits="8,9" ids="Super,Hard,Easy,Normal"/>',
           '<dip name="Lives" bits="10,11" ids="4,3,2,1"/>',
           '<dip name="Demo Sounds" bits="12" ids="Off,On"/>', '<dip name="Flip Screen" bits="13" ids="On,Off"/>',
           '<dip name="Training Mode" bits="14" ids="Off,On"/>', '<dip name="Service Mode" bits="15" ids="On,Off"/>']

PD_COMMON = dict(sub=[('u4.u86', '497fad4c'), ('u3.u99', '4800322a')],
                 gfx1=[('s73', '63f4e10c'), ('s72', '4e669e97')], gfx2=[('s71', '431485ee'), ('s72', '4e669e97')],
                 gfx3=[('a30.u12', '50bc5e98'), ('a29.u2', 'a240a448')],
                 pcma=('g71.u118', '488e2fd1'), pcmb=('g72.u83', 'dc3d14be'))
GAMES = [
    dict(set='pipedrm',  name='Pipe Dream (World)', region='World', main=[('ya.u129', '9b4d84a2'), ('yb.u110', '7416554a')]),
    dict(set='pipedrmu', name='Pipe Dream (US)',    region='US',    main=[('01.u129', '9fe261fb'), ('02.u110', 'c8209b67')]),
    dict(set='pipedrmj', name='Pipe Dream (Japan)', region='Japan', main=[('1.u129',  'dbfac46b'), ('2.u110',  'b7adb99a')]),
    dict(set='pipedrmt', name='Pipe Dream (Taiwan)', region='Taiwan', main=[('t1.u129', '335401a4'), ('t2.u110', 'c8209b67')]),
]

out = sys.argv[1]; rbf = sys.argv[2] if len(sys.argv) > 2 else 'TomSVR_pipedrm'
os.makedirs(f'{out}/mra', exist_ok=True)
nl = '\n'
P = lambda f: f'name="{f[0]}" crc="{f[1]}"'
xml = lambda s: s.replace('&', '&amp;')

def build(g, zipname):
    z = zipfile.ZipFile(os.path.join(ZIPS, zipname)); by = {'%08x' % i.CRC: i for i in z.infolist()}
    rd = lambda f: z.read(by[f[1]])
    img = bytearray(b'\xff' * END); parts = []
    pos = 0
    def put(f):
        nonlocal pos
        d = rd(f); img[pos:pos+len(d)] = d; pos += len(d); parts.append(f'        <part {P(f)}/>')
    def fill(to, v='FF'):
        nonlocal pos
        if to > pos:
            img[pos:to] = bytes([int(v, 16)]) * (to-pos)
            parts.append(f'        <part repeat="0x{to-pos:x}"> {v}</part>'); pos = to
    # main: 32 kB at 0, banked 64 kB at 10000 (MAME maincpu region)
    put(g['main'][0]); fill(0x10000); put(g['main'][1]); fill(SND)
    put(PD_COMMON['sub'][0]); fill(SND+0x10000); put(PD_COMMON['sub'][1]); fill(BA1)
    for f in PD_COMMON['gfx1']: put(f)
    fill(BA2)
    for f in PD_COMMON['gfx2']: put(f)
    fill(BA3)
    # sprites: ROM_LOAD16_BYTE, a30 on the even bytes
    e, o = (rd(f) for f in PD_COMMON['gfx3'])
    for k in range(len(e)): img[pos+2*k] = e[k]; img[pos+2*k+1] = o[k]
    pos += 2*len(e)
    parts.append('        <interleave output="16">')
    parts.append(f'            <part {P(PD_COMMON["gfx3"][0])} map="01"/>')
    parts.append(f'            <part {P(PD_COMMON["gfx3"][1])} map="10"/>')
    parts.append('        </interleave>')
    fill(PCMA); put(PD_COMMON['pcma']); fill(PCMB); put(PD_COMMON['pcmb'])
    assert pos == END, hex(pos)
    hdr = bytes([0]*HDR)
    return hdr + bytes(img), parts

for g in GAMES:
    img, parts = build(g, 'pipedrm.zip')
    open(f'{out}/{g["set"]}.rom', 'wb').write(img); open(f'{out}/{g["set"]}.md5', 'w').write(hashlib.md5(img).hexdigest())
    mra = f'''<!-- {g["name"]} on TomSVR_pipedrm, an unofficial MiSTer core for the Video System Pipe Dream board
     (MAME vsystem/pipedrm.cpp "{g["set"]}"), built on JTFRAME by Jose Tejada (jotego), with the sprite chip and GGA
     timing from Andrea Bogazzi's jtpspike. The ROM is assembled from your own MAME zip, unmodified. -->
<misterromdescription>
    <name>{xml(g["name"])} [TomSVR]</name>
    <setname>{g["set"]}</setname>
    <rotation>horizontal</rotation>
    <mameversion>0264</mameversion>
    <year>1990</year>
    <manufacturer>Video System Co.</manufacturer>
    <players>2</players>
    <rbf>{rbf}</rbf>
    <joystick>8</joystick>
    <region>{g["region"]}</region>
    <rom index="0" zip="pipedrm.zip" md5="None">
        <part> 00 00 00 00 00 00 00 00</part>
{nl.join(parts)}
    </rom>
    <switches page_id="1" page_name="Switches" base="16" default="ff,ff">
{nl.join('        ' + d for d in PD_DIPS)}
    </switches>
    <buttons names="Place,Fast,Button 3,Start,Coin,Core credits" default="A,B,X,Start,Select,-" count="3"/>
</misterromdescription>
'''
    open(f'{out}/mra/{g["name"]} [TomSVR].mra', 'w').write(mra)
    print(g['set'], hashlib.md5(img).hexdigest())
