#!/usr/bin/env python3
# djboy_build.py outdir [rbf] : JTDJBOY images (.rom with header, for simulation) + MRAs from your own MAME zips
# djboy.zip (djboy djboyu djboyua djboyj djboyja) and airbustr.zip (airbustr airbustrj airbustrb), merged sets.
# Layout after the 8-byte header (see djboy/cfg/macros.def):
#   000000 main (256 kB)  040000 sub (256 kB)  080000 sound (128 kB)  0A0000 OKI (256 kB)
#   100000 tiles (1 MB)   200000 sprites (2 MB)  400000 BEAST MCU (4 kB, DJ Boy only)
# Parts are found in the zip by CRC; the MRA uses the member names of the zip (clone files sit in sub folders).
import sys, os, zipfile
HERE = os.path.dirname(os.path.abspath(__file__))
ZIPS = os.environ.get('ZIPS', os.path.join(HERE, '..', 'roms'))

def coins(order):
    return ','.join(order)

DJ_DIPS = [
    '<dip name="Service Mode" bits="2" ids="Off,On"/>',
    '<dip name="Coin A" bits="4,5" ids="1C/1C,1C/2C,2C/1C,2C/3C"/>',
    '<dip name="Coin B" bits="6,7" ids="1C/1C,1C/2C,2C/1C,2C/3C"/>',
    '<dip name="Difficulty" bits="8,9" ids="Normal,Easy,Hard,Hardest"/>',
    '<dip name="Bonus Levels (in thousands)" bits="10,11" ids="10/30/50/70/90,10 to 90 every 10,20/50,None"/>',
    '<dip name="Lives" bits="12,13" ids="5,3,7,9"/>',
    '<dip name="Demo Sounds" bits="14" ids="On,Off"/>',
]
AB_TAIL = [
    '<dip name="Difficulty" bits="8,9" ids="Very Difficult,Difficult,Easy,Normal"/>',
    '<dip name="Freeze" bits="11" ids="On,Off"/>',
    '<dip name="Lives" bits="12,13" ids="7,5,4,3"/>',
    '<dip name="Demo Sounds" bits="14" ids="Off,On"/>',
]
AB_DIPS = [
    '<dip name="Service Mode" bits="2" ids="On,Off"/>',
    '<dip name="Coin Mode" bits="3" ids="Mode 2,Mode 1"/>',
    '<dip name="Coin A" bits="4,5" ids="1C/6C (mode 2: 1C/4C),1C/2C (mode 2: 1C/3C),2C/1C,1C/1C"/>',
    '<dip name="Coin B" bits="6,7" ids="1C/6C (mode 2: 1C/4C),1C/2C (mode 2: 1C/3C),2C/1C,1C/1C"/>',
] + AB_TAIL
ABJ_DIPS = [
    '<dip name="Service Mode" bits="2" ids="On,Off"/>',
    '<dip name="Coin A" bits="4,5" ids="2C/3C,2C/1C,1C/2C,1C/1C"/>',
    '<dip name="Coin B" bits="6,7" ids="2C/3C,2C/1C,1C/2C,1C/1C"/>',
] + AB_TAIL

DJ_SPR = ['be4bf805', 'fdf36e6b', 'c52fee7f', ('ed89acb4', 0x70000)]   # bs003: first 0x70000, then bs06/bs07s
DJ_BG = ['2f1392c3', '46b400c4']
DJ = dict(zip='djboy.zip', year='1989', mfr='Kaneko', buttons='Punch,Kick,Jump', dips=DJ_DIPS, dsw='00,80')
AB = dict(zip='airbustr.zip', year='1990', mfr='Kaneko (Namco license)', buttons='Shot,Bomb,Unused', dsw='ff,ff')

GAMES = [
    dict(DJ, set='djboy',   name='DJ Boy (World)',        region='World', flags=0,
         main=['354531ec', '081e8af8'], sub=['91eb189a', 'a7c85577'], spr6='22c8aa08', oki=['805341fb']),
    dict(DJ, set='djboyu',  name='DJ Boy (US, set 1)',    region='USA', year='1990', mfr='Kaneko (American Sammy license)',
         flags=0, main=['b77aacc7', '081e8af8'], sub=['0f1456eb', 'a7c85577'], spr6='d9b7a220', oki=['805341fb']),
    dict(DJ, set='djboyua', name='DJ Boy (US, set 2)',    region='USA', year='1990', mfr='Kaneko (American Sammy license)',
         flags=0, main=['17ce9f6c', '081e8af8'], sub=['e6f966b2', 'a7c85577'], spr6='d9b7a220', oki=['805341fb']),
    dict(DJ, set='djboyj',  name='DJ Boy (Japan, set 1)', region='Japan', mfr='Kaneko (Sega license)', flags=2,
         main=['0971523e', '081e8af8'], sub=['5c3f2f96', 'a7c85577'], spr6='22c8aa08', oki=['510244f0']),
    dict(DJ, set='djboyja', name='DJ Boy (Japan, set 2)', region='Japan', mfr='Kaneko (Sega license)', flags=2,
         main=['f7ac20ca', '081e8af8'], sub=['5c3f2f96', 'a7c85577'], spr6='22c8aa08', oki=['b0e0a452', 'd24988ad']),
    dict(AB, set='airbustr',  name='Air Buster: Trouble Specialty Raid Unit (World)', region='World', flags=5,
         main=['91362eb2'], sub=['13b2257b'], dips=AB_DIPS),
    dict(AB, set='airbustrj', name='Air Buster: Trouble Specialty Raid Unit (Japan)', region='Japan', flags=5,
         main=['6b9805bd'], sub=['85464124'], dips=ABJ_DIPS),
    dict(AB, set='airbustrb', name='Air Buster: Trouble Specialty Raid Unit (bootleg)', region='World', flags=1,
         mfr='bootleg', main=['9e4216a2'], sub=['85464124'], dips=ABJ_DIPS),
]

out = sys.argv[1]; rbf = sys.argv[2] if len(sys.argv) > 2 else 'TomSVR_djboy'
os.makedirs(f'{out}/mra', exist_ok=True)
xml = lambda s: s.replace('&', '&amp;').replace("'", '&apos;')

for g in GAMES:
    z = zipfile.ZipFile(os.path.join(ZIPS, g['zip']))
    by = {'%08x' % i.CRC: i for i in z.infolist()}
    img = bytearray(); parts = []
    hdr = bytes([g['flags'], 0, 0, 0, 0, 0, 0, 0])
    parts.append('<part>' + ' '.join('%02X' % b for b in hdr) + '</part>')
    def put(crc, length=None):
        i = by[crc]; d = z.read(i)
        if length: d = d[:length]
        img.extend(d)
        parts.append(f'<part name="{i.filename}" crc="{crc}"' + (f' length="0x{length:x}"' if length else '') + '/>')
    def pad(to):
        if to > len(img):
            parts.append(f'<part repeat="0x{to-len(img):x}">00</part>'); img.extend(bytes(to - len(img)))
        assert len(img) == to, (g['set'], hex(len(img)), hex(to))
    def inter16(even, odd):     # ROM_LOAD16_BYTE: even file = image byte 0
        e, o = z.read(by[even]), z.read(by[odd])
        for k in range(len(e)): img.extend((e[k], o[k]))
        parts.append('<interleave output="16">')
        parts.append(f'    <part name="{by[even].filename}" crc="{even}" map="01"/>')
        parts.append(f'    <part name="{by[odd].filename}" crc="{odd}" map="10"/>')
        parts.append('</interleave>')
    abus = g['flags'] & 1
    for c in g['main']: put(c)
    pad(0x40000)
    for c in g['sub']: put(c)
    pad(0x80000)
    put('f6c19e51' if not abus else '6e0a5df0')
    pad(0xa0000)
    if abus and g['set'] == 'airbustrb': put('21d9bfe3'); put('58cd19e2')
    elif abus: put('a4dd3390')
    else:
        for c in g['oki']: put(c)
    pad(0x100000)
    if not abus:
        for c in DJ_BG: put(c)
    elif g['set'] == 'airbustrb':
        inter16('2e3bf0a2', '2c23c646'); inter16('0d6cd470', 'b3372e51')
    else: put('8ca68f0d')
    pad(0x200000)
    if not abus:
        for c in DJ_SPR:
            if isinstance(c, tuple): put(*c)
            else: put(c)
        put(g['spr6'])
        assert len(img) == 0x400000
        put('ebe0f5f3')     # BEAST internal ROM
    elif g['set'] == 'airbustrb':
        for c in ['75dee86d', 'c98a8333', '4e9baebd', '63dc8cd8', '6bbd5e46']: put(c)
    else:
        put('7e6cb377'); put('6bbd5e46')
    open(f'{out}/{g["set"]}.rom', 'wb').write(hdr + img)
    nl = '\n        '
    dips = '\n        '.join(g['dips'])
    mra = f'''<!-- {xml(g["name"])} on the TomSVR DJ Boy / Air Buster core (MAME kaneko/{"airbustr" if abus else "djboy"}.cpp),
     built on JTFRAME. Unofficial, MAME-based. The ROM is assembled from your own MAME zip, unmodified. -->
<misterromdescription>
    <name>{xml(g["name"])} [TomSVR]</name>
    <setname>{g["set"]}</setname>
    <rotation>horizontal</rotation>
    <mameversion>0264</mameversion>
    <year>{g["year"]}</year>
    <manufacturer>{xml(g["mfr"])}</manufacturer>
    <players>2</players>
    <rbf>{rbf}</rbf>
    <joystick>8-way</joystick>
    <region>{g["region"]}</region>
    <rom index="0" zip="{g["zip"]}" md5="None">
        {nl.join(parts)}
    </rom>
    <switches page_id="1" page_name="Switches" base="16" default="{g["dsw"]}">
        {dips}
    </switches>
    <buttons names="{g["buttons"]},Start,Coin,Core credits" default="A,B,X,Start,Select,-" count="3"/>
</misterromdescription>
'''
    fn = g['name'].replace(':', ' -').replace('/', '-')
    open(f'{out}/mra/{fn} [TomSVR].mra', 'w').write(mra)
    print(f'{g["set"]:10} {len(img):#x}')
