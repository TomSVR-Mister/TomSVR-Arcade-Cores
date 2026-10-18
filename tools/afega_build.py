#!/usr/bin/env python3
# afega_build.py outdir : JTAFEGA sim images (<set>.rom with header), MRAs and md5 files from the user's zips
import sys, os, zipfile, hashlib
S = '/tmp/claude-0/-home-claude/e1042311-2b93-5281-bddb-91ed22183aec/scratchpad'
UZ = f'{S}/userzips'

# header byte 0: scr | tmod << 2 | omask << 4 | nospr << 5
SETS = {
  'bubl2000': dict(zip='bubl2000.zip', title='Bubble 2000', year='1998', man='Afega (Tuning license)', hdr=0x01 | 0 << 2,
      prog=[('rom10.112', '87f960d7'), ('rom11.107', 'b386041a')], snd=('rom01.92', '5d8cf28e'), oki=('rom02.95', '859a86e5'),
      spr=[('rom08.11', '519dfd82'), ('rom09.14', '04fcb5c6')], sprlen=0x80000,
      bg=[(('rom06.6', 'ac1aabf5'), ('rom04.1', '46acd054')), (('rom07.9', '69aff769'), ('rom05.3', '37deb6a1')),
          (('rom13.7', '3a5b7226'), ('rom12.2', '1fdc59dd'))],
      tx=('rom03.4', 'f4c15588'), dsw='bubl2000'),
  'bubl2000a': dict(zip='bubl2000.zip', title='Bubble 2000 V1.2', year='1998', man='Afega (Tuning license)', hdr=0x01,
      prog=[('b-2000_n_v1.2.112', 'da28624b'), ('b-2000_n_v1.2.107', 'c766c1fb')], snd=('rom01.92', '5d8cf28e'), oki=('rom02.95', '859a86e5'),
      spr=[('rom08.11', '519dfd82'), ('rom09.14', '04fcb5c6')], sprlen=0x80000,
      bg=[(('rom06.6', 'ac1aabf5'), ('rom04.1', '46acd054')), (('rom07.9', '69aff769'), ('rom05.3', '37deb6a1')),
          (('rom13.7', '3a5b7226'), ('rom12.2', '1fdc59dd'))],
      tx=('rom03.4', 'f4c15588'), dsw='bubl2000a'),
  'hotbubl': dict(zip='bubl2000.zip', title='Hot Bubble (Korea, with adult pictures)', year='1998', man='Afega (Pandora license)', hdr=0x01,
      prog=[('afega9.c2.uc9', '4537c6d9'), ('afega8.c1.uc1', 'd1e72a31')], snd=('afega8.s1.uc14', '5d8cf28e'), oki=('afega8.s2.uc18', '401c980f'),
      spr=[('afega10.br1.uc3', '7e132eff'), ('afega8.br3.uc10', '22707728')], sprlen=0x80000,
      bg=[(('afega10.cr5.uc15', '65bd5159'), ('afega8.cr1.uc6', 'fc9101d2')), (('afega10.cr7.uc19', 'a89d9ce4'), ('afega9.cr3.uc12', 'c841a4f6')),
          (('afega9.cr6.uc16', '99d6523c'), ('afega9.cr2.uc7', '27ad6fc8'))],
      tx=('afega9.t1.uc2', 'ce683a93'), dsw='bubl2000'),
  'hotbubla': dict(zip='bubl2000.zip', title='Hot Bubble (Korea)', year='1998', man='Afega (Pandora license)', hdr=0x01 | 0x10,
      prog=[('7_c2.uc9', '74eb11c3'), ('6_c1.uc1', '7c65bf47')], snd=('1_s1.uc14', '5d8cf28e'), oki=('1_s2.uc18', '401c980f'),
      spr=[('8_br1.uc3', '7e132eff'), ('9_br3.uc10', '22707728')], sprlen=0x100000,
      bg=[(('2_cr5.uc15', 'dd7e92de'), ('8_cr1.uc6', '7e2840b4')), (('5_cr7.uc19', 'd293f1d0'), ('10_cr3.uc12', '312c38d8')),
          (('5_cr6.uc16', '324429c5'), ('9_cr2.uc7', 'c5516087'))],
      tx=('2_t1.uc2', 'ce683a93'), dsw='bubl2000'),
  'popspops': dict(zip='popspops.zip', title="Pop's Pop's", year='1999', man='Afega', hdr=0x02 | 1 << 2 | 0x20,
      prog=[('afega4.u112', 'db191762'), ('afega5.u107', '17e0c48b')], snd=('afega1.u92', '5d8cf28e'), oki=('afega2.u95', 'ecd8eeac'),
      spr=None, sprlen=0,
      bg=[(('afega6.uc8', '6d506c97'), ('afega7.uc3', '02d7f9de'))],
      tx=('afega3.u4', 'f39dd5d2'), dsw='popspops'),
  'mangchi': dict(zip='mangchi.zip', title='Mang-Chi', year='2000', man='Afega', hdr=0x01 | 2 << 2,
      prog=[('afega9.u112', '0b1517a5'), ('afega10.u107', 'b1d0f33d')], snd=('sound.u92', 'bec4f9aa'), oki=('afega2.u95', '78c8c1f9'),
      spr=[('afega6.uc11', '979efc30'), ('afega7.uc14', 'c5cbcc38')], sprlen=0x80000,
      bg=[(('afega5.uc6', 'c73261e0'), ('afega4.uc1', '73940917'))],
      tx=None, dsw='mangchi'),
  'dolmen': dict(zip='dolmen.zip', title='Dolmen', year='1995', man='Afega', hdr=0x10 | 0x40,
      prog=[('afega8.uj3', 'f1b73e4c'), ('afega7.uj2', 'c91bda0b')], snd=('afega1.su6', '166b53cb'), oki=('afega2.su12', '1a2ce1c2'),
      oki2=('afega3.su13', 'd3531018'),
      spr=[('afega4.ub11', '5a259393'), ('afega5.ub13', '7f6a683d')], sprlen=0x100000,
      bg=[], bg4=('afega9.ui20', 'b3fa7be6'),
      tx=('afega6.uj11', '13fa4415'), dsw='dolmen'),
}
COIN8 = '4C/1C,3C/1C,2C/1C,3C/2C,2C/3C,1C/3C,1C/2C,1C/1C'      # values 0,2,4,6,8,a,c,e >> 1 (0x0000.. order)
DSWS = {
  'bubl2000': ['<dip name="Difficulty" bits="2,3" ids="Hardest,Hard,Easy,Normal"/>',
               '<dip name="Free Credit" bits="6,7" ids="1500k,1000k,500k,800k"/>',
               '<dip name="Demo Sounds" bits="9" ids="Off,On"/>',
               '<dip name="Coin B" bits="10,11,12" ids="Off,1C/4C,3C/1C,1C/2C,4C/1C,1C/3C,2C/1C,1C/1C"/>',
               '<dip name="Coin A" bits="13,14,15" ids="Off,1C/4C,3C/1C,1C/2C,4C/1C,1C/3C,2C/1C,1C/1C"/>'],
  'bubl2000a': ['<dip name="Coin B" bits="2,3,4" ids="Off,1C/4C,3C/1C,1C/2C,4C/1C,1C/3C,2C/1C,1C/1C"/>',
                '<dip name="Coin A" bits="5,6,7" ids="Off,1C/4C,3C/1C,1C/2C,4C/1C,1C/3C,2C/1C,1C/1C"/>',
                '<dip name="Difficulty" bits="10,11" ids="Hardest,Hard,Easy,Normal"/>',
                '<dip name="Free Credit" bits="14,15" ids="1500k,1000k,500k,800k"/>'],
  'popspops': ['<dip name="Service Mode" bits="0" ids="On,Off"/>', '<dip name="Demo Sounds" bits="1" ids="Off,On"/>',
               '<dip name="Show Answers" bits="2" ids="On,Off"/>', '<dip name="Free Play" bits="6" ids="On,Off"/>',
               '<dip name="Difficulty" bits="11,12" ids="Hardest,Hard,Easy,Normal"/>',
               f'<dip name="Coinage" bits="13,14,15" ids="{COIN8}"/>'],
  'mangchi': ['<dip name="Demo Sounds" bits="1" ids="Off,On"/>', '<dip name="Vs Rounds" bits="3,4" ids="5,4,3,2"/>',
              '<dip name="Free Play" bits="6" ids="On,Off"/>', '<dip name="Difficulty" bits="11,12" ids="Hardest,Easy,Hard,Normal"/>',
              f'<dip name="Coinage" bits="13,14,15" ids="{COIN8}"/>'],
}
DSWS['dolmen'] = ['<dip name="Difficulty" bits="2,3" ids="Hardest,Hard,Easy,Normal"/>',
               '<dip name="Free Credit" bits="6,7" ids="1500k,1000k,500k,800k"/>',
               '<dip name="Demo Sounds" bits="9" ids="Off,On"/>',
               '<dip name="Coin B" bits="10,11,12" ids="Off,1C/4C,3C/1C,1C/2C,4C/1C,1C/3C,2C/1C,1C/1C"/>',
               '<dip name="Coin A" bits="13,14,15" ids="Off,1C/4C,3C/1C,1C/2C,4C/1C,1C/3C,2C/1C,1C/1C"/>']
DEFAULT = {'dolmen': 'ff,ff', 'bubl2000': 'ff,ff', 'bubl2000a': 'ff,ff', 'popspops': 'ff,ff', 'mangchi': 'ff,ff'}   # popspops: answers off (MAME default on)
SND, OKI, BA1, BA2, BA3, END = 0x80000, 0x90000, 0x100000, 0x200000, 0x600000, 0x610000

class Z:
    def __init__(self, fn):
        self.z = zipfile.ZipFile(f'{UZ}/{fn}')
        self.by = {'%08x' % i.CRC: i for i in self.z.infolist()}
    def rd(self, f): return self.z.read(self.by[f[1]])

def image(a):
    z = Z(a['zip']); img = bytearray(END)
    e, o = z.rd(a['prog'][0]), z.rd(a['prog'][1])
    for k in range(len(e)): img[2 * k + 1] = e[k]; img[2 * k] = o[k]      # 68000: even byte in the high half (download byte 1)
    if a.get('oki2'): q = z.rd(a['oki2']); img[2 * len(e):SND] = q    # Dolmen: samples 40000-7ffff after the 256 kB program
    s = z.rd(a['snd']); img[SND:SND + len(s)] = s
    p = z.rd(a['oki']); img[OKI:OKI + len(p)] = p
    img[OKI + len(p):BA1] = b'\xff' * (BA1 - OKI - len(p))
    img[BA1:BA2] = b'\xff' * (BA2 - BA1)
    if a['spr']:
        e, o = z.rd(a['spr'][0]), z.rd(a['spr'][1])
        for k in range(len(e)): img[BA1 + 2 * k] = e[k]; img[BA1 + 2 * k + 1] = o[k]
        n = 2 * len(e); img[BA1 + n:BA1 + a['sprlen']] = bytes(a['sprlen'] - n)
    pos = BA2
    for f, s2 in a['bg']:
        x, y = z.rd(f), z.rd(s2)
        for k in range(len(x)): img[pos + 2 * k] = x[k]; img[pos + 2 * k + 1] = y[k]
        pos += 2 * len(x)
    if a.get('bg4'): g = z.rd(a['bg4']); img[BA2:BA2 + len(g)] = g; pos = BA2 + len(g)
    img[pos:BA3] = b'\xff' * (BA3 - pos)
    if a['tx']:
        t = z.rd(a['tx'])
        if BA3 + len(t) > len(img): img += bytes(BA3 + len(t) - len(img))
        img[BA3:BA3 + len(t)] = t
    else: img[BA3:END] = b'\xff' * (END - BA3)
    return z, bytes(img)

def mra(name, a, z):
    P = [f'        <part> {a["hdr"]:02X} 00 00 00 </part>']
    def part(f): return f'name="{f[0]}" crc="{f[1]}"'
    def ilv(x, y, mx, my):
        P.append('        <interleave output="16">')
        P.append(f'            <part {part(x)} map="{mx}"/>')
        P.append(f'            <part {part(y)} map="{my}"/>')
        P.append('        </interleave>')
    ilv(a['prog'][0], a['prog'][1], '10', '01')
    pl = 2 * len(z.rd(a['prog'][0]))
    if a.get('oki2'): P.append(f'        <part {part(a["oki2"])}/>'); pl += len(z.rd(a['oki2']))
    if pl < SND: P.append(f'        <part repeat="0x{SND - pl:x}"> 00</part>')
    P.append(f'        <part {part(a["snd"])}/>')
    sl = len(z.rd(a['snd']))
    if sl < OKI - SND: P.append(f'        <part repeat="0x{OKI - SND - sl:x}"> 00</part>')
    P.append(f'        <part {part(a["oki"])}/>')
    ol = len(z.rd(a['oki']))
    P.append(f'        <part repeat="0x{BA1 - OKI - ol:x}"> FF</part>')
    if a['spr']:
        ilv(a['spr'][0], a['spr'][1], '01', '10')
        n = 2 * len(z.rd(a['spr'][0]))
        if a['sprlen'] > n: P.append(f'        <part repeat="0x{a["sprlen"] - n:x}"> 00</part>')
        if BA2 - BA1 - a['sprlen'] > 0: P.append(f'        <part repeat="0x{BA2 - BA1 - a["sprlen"]:x}"> FF</part>')
    else: P.append(f'        <part repeat="0x{BA2 - BA1:x}"> FF</part>')
    pos = BA2
    for f, s2 in a['bg']:
        ilv(f, s2, '01', '10'); pos += 2 * len(z.rd(f))
    if a.get('bg4'): P.append(f'        <part {part(a["bg4"])}/>'); pos += len(z.rd(a['bg4']))
    if BA3 > pos: P.append(f'        <part repeat="0x{BA3 - pos:x}"> FF</part>')
    if a['tx']: P.append(f'        <part {part(a["tx"])}/>')
    else: P.append(f'        <part repeat="0x{END - BA3:x}"> FF</part>')
    nl = '\n'
    zips = a['zip']
    board = 'the Afega Dolmen board (MAME nmk16.cpp "twinactn")' if a.get('bg4') else 'the Afega 8 bpp background boards (MAME nmk16.cpp "popspops")'
    return f'''<!-- {a['title']} on JTAFEGA, a personal MiSTer core for {board},
     built on JTFRAME by Jose Tejada (jotego). The ROM is assembled from your own MAME zip, unmodified. Requires jtafega.rbf. -->
<misterromdescription>
    <name>{a['title']} (JTAFEGA)</name>
    <setname>{name}</setname>
    <rotation>horizontal</rotation>
    <mameversion>0264</mameversion>
    <year>{a['year']}</year>
    <manufacturer>{a['man']}</manufacturer>
    <players>2</players>
    <rbf>jtafega</rbf>
    <joystick>8</joystick>
    <region>World</region>
    <rom index="0" zip="{zips}" md5="None">
{nl.join(P)}
    </rom>
    <rom index="1">
        <part>00 80</part>
    </rom>
    <switches page_id="1" page_name="Switches" base="16" default="{DEFAULT[a['dsw']]}">
{nl.join('        ' + d for d in DSWS[a['dsw']])}
    </switches>
    <buttons names="Button 1,Button 2,Start,Coin,Core credits" default="A,B,Start,Select,-" count="2"/>
</misterromdescription>
'''

if __name__ == '__main__':
    out = sys.argv[1]; os.makedirs(f'{out}/mra', exist_ok=True)
    for name, a in SETS.items():
        z, img = image(a)
        rom = bytes([a['hdr'], 0, 0, 0]) + img
        open(f'{out}/{name}.rom', 'wb').write(rom)
        open(f'{out}/{name}.md5', 'w').write(hashlib.md5(rom).hexdigest())
        t = a['title'].replace("'", "'")
        open(f'{out}/mra/{a["title"]} (JTAFEGA).mra', 'w').write(mra(name, a, z))
        print(name, hex(len(rom)), hashlib.md5(rom).hexdigest())
