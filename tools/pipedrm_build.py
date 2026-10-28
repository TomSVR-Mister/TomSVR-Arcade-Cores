#!/usr/bin/env python3
# pipedrm_build.py outdir [rbf] : JTPIPEDRM images (.rom, for simulation) + MRAs from the user's own MAME zips
# (pipedrm.zip, hatris.zip, merged sets; Hatris also needs ym2608.zip for the YM2608's internal drum ROM). Layout (after the 8-byte header, see pipedrm/cfg/macros.def):
#   000000 maincpu (0x20000)  020000 sub (0x20000)  100000 gfx1  200000 gfx2  300000 gfx3 (sprites)
#   380000 ADPCM-A / YM2608 rhythm ROM  400000 ADPCM-B
# Header byte 0 = 1 for Hatris. Hatris drums: each one starts on a 256-byte block, padded with 80 (see
# jtpipedrm_opna.v, which writes the same blocks to the ADPCM-A channels)
import sys, os, zipfile, hashlib
HERE = os.path.dirname(os.path.abspath(__file__))
ZIPS = os.environ.get('ZIPS', os.path.join(HERE, '..', 'roms'))   # folder with your own pipedrm.zip, hatris.zip, ym2608.zip
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

def build(g, zipname, hatris=False):
    by = {}
    for zn in zipname.split('|'):
        z = zipfile.ZipFile(os.path.join(ZIPS, zn))
        for i in z.infolist(): by['%08x' % i.CRC] = (z, i)
    rd = lambda f: by[f[1]][0].read(by[f[1]][1])
    img = bytearray(b'\xff' * END); parts = []
    pos = 0
    def put(f, off=0, ln=None):
        nonlocal pos
        d = rd(f)[off:] if ln is None else rd(f)[off:off+ln]
        img[pos:pos+len(d)] = d; pos += len(d)
        extra = '' if ln is None else f' offset="0x{off:x}" length="0x{ln:x}"'
        parts.append(f'        <part {P(f)}{extra}/>')
    def fill(to, v='FF'):
        nonlocal pos
        if to > pos:
            img[pos:to] = bytes([int(v, 16)]) * (to-pos)
            parts.append(f'        <part repeat="0x{to-pos:x}"> {v}</part>'); pos = to
    if hatris: return build_hatris(g, img, parts, put, fill, lambda: pos)
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

RHYTHM = ('ym2608_adpcm_rom.bin', '23c9e0d8')
# ymfm ym2608::reset: bass drum, snare, top cymbal, hi-hat, tom, rim shot (byte ranges in the 8 kB ROM)
DRUMS = [(0x0000, 0x01c0), (0x01c0, 0x0280), (0x0440, 0x1740), (0x1b80, 0x0180), (0x1d00, 0x0280), (0x1f80, 0x0080)]
HA_DIPS = [f'<dip name="Coin A" bits="0,3" ids="1C/1C,1C/2C,1C/3C,1C/4C,1C/5C,1C/6C,2C/1C,3C/1C,4C/1C,5C/1C,2C/3C,6C/4C,4C/3C,5C/6C,4C/5C,2C/3C"/>',
           f'<dip name="Coin B" bits="4,7" ids="1C/1C,1C/2C,1C/3C,1C/4C,1C/5C,1C/6C,2C/1C,3C/1C,4C/1C,5C/1C,2C/3C,6C/4C,4C/3C,5C/6C,4C/5C,2C/3C"/>',
           '<dip name="Hat Fall Velocity" bits="8,9" ids="Normal,Easy,Hard,Super"/>',
           '<dip name="End Line Position" bits="10,11" ids="Normal,Easy,Hard,Super"/>',
           '<dip name="Service Mode" bits="12" ids="Off,On"/>', '<dip name="Flip Screen" bits="13" ids="Off,On"/>',
           '<dip name="Demo Sounds" bits="14" ids="On,Off"/>']
HA_COMMON = dict(sub=('1.ic81', 'db25e166'), gfx1=[('b0.ic56', '34f337a4'), ('b1.ic73', '6351d0ba')],
                 gfx2=[('a0.ic55', '7b7bc619'), ('a1.ic60', 'f74d4168')], pcmb=('pc.ic53', '07147712'))
HATRIS = [
    dict(set='hatris',  name='Hatris (US)',            region='US',    main=('2.ic79', '4ab50b54')),
    dict(set='hatrisj', name='Hatris (Japan)',         region='Japan', main=('2-ic79.bin', 'bbcaddbf')),
    dict(set='hatrisp', name='Hatris (show version)',  region='US',    main=('3-6show.ic8', 'e1cf7403'),
         sub=('3-6.ic94', 'e0b05b71'), gfx1=[('b0.ic76+', '60346041'), ('b1.ic76', 'e8e2db07')]),
]

def build_hatris(g, img, parts, put, fill, here):
    gg = dict(HA_COMMON, **g)
    put(gg['main']); fill(SND, '00'); put(gg['sub']); fill(BA1, '00')
    # gfx1 (MAME): b0 at 0, zeros, b1 at 40000; the region is cleared again from 48000, so only 32 kB of b1 count
    put(gg['gfx1'][0]); fill(BA1 + 0x40000, '00'); put(gg['gfx1'][1], 0, 0x8000); fill(BA2, '00')
    for f in gg['gfx2']: put(f)
    fill(PCMA)
    for k, (off, ln) in enumerate(DRUMS):
        put(RHYTHM, off, ln); fill(PCMA + 0x100 * sum((l + 0xff) // 0x100 for _, l in DRUMS[:k+1]), '80')
    fill(PCMB); put(gg['pcmb']); fill(END)
    assert here() == END, hex(here())
    return bytes([1] + [0]*(HDR-1)) + bytes(img), parts

def mra_text(g, parts, rbf, zips, dips, dipdef, buttons, count):
    return f'''<!-- {g["name"]} on TomSVR_pipedrm, an unofficial MiSTer core for the Video System Pipe Dream / Hatris boards
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
    <rom index="0" zip="{zips}" md5="None">
{nl.join(parts)}
    </rom>
    <switches page_id="1" page_name="Switches" base="16" default="{dipdef}">
{nl.join('        ' + d for d in dips)}
    </switches>
    <buttons names="{buttons}" default="A,B,X,Start,Select,-" count="{count}"/>
</misterromdescription>
'''

for g in HATRIS:
    img, parts = build(g, 'hatris.zip|ym2608.zip', hatris=True)
    parts = ['        <part> 01 00 00 00 00 00 00 00</part>'] + parts
    open(f'{out}/{g["set"]}.rom', 'wb').write(img); open(f'{out}/{g["set"]}.md5', 'w').write(hashlib.md5(img).hexdigest())
    open(f'{out}/mra/{g["name"]} [TomSVR].mra', 'w').write(
        mra_text(g, parts, rbf, 'hatris.zip|ym2608.zip', HA_DIPS, '00,00', 'Button 1,Button 2,Button 3,Start,Coin,Core credits', 3))
    print(g['set'], hashlib.md5(img).hexdigest())

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
