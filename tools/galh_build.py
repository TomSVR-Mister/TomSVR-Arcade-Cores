#!/usr/bin/env python3
# galh_build.py : jtcomad (gh mode, header byte 0 = 02) images + MRAs for Pocket Gals V.I.P. / Gals Hustler from the user's pgalvip.zip
# usage: galh_build.py outdir   -> outdir/<set>.rom (sim image, with header), outdir/mra/*.mra, outdir/<set>.md5
import sys, os, zipfile, hashlib
S = '/tmp/claude-0/-home-claude/e1042311-2b93-5281-bddb-91ed22183aec/scratchpad'
z = zipfile.ZipFile(f'{S}/userzips/pgalvip.zip')
byname = {i.filename: i for i in z.infolist()}
def rd(n): return z.read(byname[n])
def crc(n): return '%08x' % byname[n].CRC
base = lambda n: n.split('/')[-1]
H0 = 0x02
UC6 = 'afega_11.uc6'
SETS = {
  'pgalvip':   dict(title='Pocket Gals V.I.P. (set 1)', year='1996', man='ACE International / Afega',
                    prog=('afega_15.ue17', 'afega_16.ud17'), data=('afega_13.rob1', 'afega_14.roa1'),
                    ub6='afega_12.ub6', spr='afega_17.u5'),
  'pgalvipa':  dict(title='Pocket Gals V.I.P. (set 2)', year='1997', man='unknown',
                    prog=('pgalvipa/pgalvip_3.ue17', 'pgalvipa/pgalvip_4.ud17'), data=None,
                    ub6='afega_12.ub6', spr='pgalvipa/pgalvip_5.u5'),
  'galhustl':  dict(title='Gals Hustler (set 1)', year='1997', man='ACE International',
                    prog=('galhustl/ue17.3', 'galhustl/ud17.4'), data=None,
                    ub6='galhustl/galhstl1.ub6', spr='galhustl/galhstl5.u5'),
  'galhustla': dict(title='Gals Hustler (set 2)', year='1997', man='ACE International',
                    prog=('galhustla/afega_3.uc17', 'galhustla/afega_4.ud17'), data=None,
                    ub6='galhustla/afega_1.ub6', spr='galhustla/afega_5.u5'),
}
DIPS = [
    '<dip name="Lives" bits="0,1" ids="6,7,10,8"/>',
    '<dip name="Demo Sounds" bits="6" ids="Off,On"/>',
    '<dip name="Service Mode" bits="7" ids="On,Off"/>',
    '<dip name="Coinage" bits="8,9,10" ids="4C/1C,3C/1C,2C/1C,2C/3C,3C/2C,1C/3C,1C/2C,1C/1C"/>',
    '<dip name="Difficulty" bits="11,12" ids="Hardest,Hard,Easy,Normal"/>',
    '<dip name="Play Time" bits="13,14" ids="70 s,80 s,120 s,100 s"/>',
]

def il(e, o):
    a, b = rd(e), rd(o); r = bytearray(2 * len(a))
    r[0::2] = a; r[1::2] = b      # big-endian CPU image
    return bytes(r)

def image(a):
    """CPU image as MAME sees it (big-endian), OKI and sprite regions"""
    cpu = bytearray(0x600000)                       # 000000-4fffff game area (MAME: unmapped / zero-filled region = 0) + extension
    p = il(*a['prog']); cpu[:len(p)] = p
    cpu[0x200000:0x300000] = il(*a['data']) if a['data'] else b'\xff' * 0x100000
    cpu[0x500000:0x600000] = b'\xff' * 0x100000     # extension ROM (unused)
    oki = bytearray(0x100000); u = rd(a['ub6']); oki[:len(u)] = u; oki[0x80000:] = rd(UC6)
    spr = rd(a['spr']) + bytes(0x80000)
    return bytes(cpu), bytes(oki), spr

def sim_rom(name, a):
    cpu, oki, spr = image(a)
    sw = bytearray(len(cpu)); sw[0::2] = cpu[1::2]; sw[1::2] = cpu[0::2]   # download order (low byte first)
    return bytes([H0, 0, 0, 0]) + bytes(sw) + oki + spr

def mra(name, a):
    P = [f'        <part> {H0:02X} 00 00 00 </part>']
    def ilv(e, o):
        P.append('        <interleave output="16">')
        P.append(f'            <part name="{base(o)}" crc="{crc(o)}" map="01"/>')
        P.append(f'            <part name="{base(e)}" crc="{crc(e)}" map="10"/>')
        P.append('        </interleave>')
    ilv(*a['prog']); plen = 2 * len(rd(a['prog'][0]))
    P.append(f'        <part repeat="0x{0x200000 - plen:x}"> 00</part>')
    if a['data']: ilv(*a['data'])
    else: P.append('        <part repeat="0x100000"> FF</part>')
    P.append('        <part repeat="0x200000"> 00</part>')
    P.append('        <part repeat="0x100000"> FF</part>')
    ul = len(rd(a['ub6']))
    P.append(f'        <part name="{base(a["ub6"])}" crc="{crc(a["ub6"])}"/>')
    if ul < 0x80000: P.append(f'        <part repeat="0x{0x80000 - ul:x}"> 00</part>')
    P.append(f'        <part name="{UC6}" crc="{crc(UC6)}"/>')
    P.append(f'        <part name="{base(a["spr"])}" crc="{crc(a["spr"])}"/>')
    P.append('        <part repeat="0x80000"> 00</part>')
    nl = '\n'
    return f'''<!-- {a['title']} on jtcomad, a personal fork of Jotego's jtgals core, built on JTFRAME.
     Header byte 0 = 02 selects the Afega Gals Hustler board (MAME expro02 "galhustl"): work RAM at 0xE80000, OKI at 0xD00000,
     IRQ 3/4/5, VU-002 sprite list read natively. The ROM is assembled from your own MAME zip, unmodified. Requires jtcomad.rbf. -->
<misterromdescription>
    <name>{a['title']} (Comad core)</name>
    <setname>{name}</setname>
    <rotation>horizontal</rotation>
    <mameversion>0282</mameversion>
    <year>{a['year']}</year>
    <manufacturer>{a['man']}</manufacturer>
    <players>2</players>
    <rbf>jtcomad</rbf>
    <joystick>8</joystick>
    <region>World</region>
    <rom index="0" zip="pgalvip.zip" md5="None">
{nl.join(P)}
    </rom>
    <rom index="1">
        <part>00 80</part>
    </rom>
    <switches page_id="1" page_name="Switches" base="16" default="ff,ff">
{nl.join('        ' + d for d in DIPS)}
    </switches>
    <buttons names="Button 1,Button 2,Start,Coin,Core credits" default="A,B,Start,Select,-" count="2"/>
</misterromdescription>
'''

if __name__ == '__main__':
    out = sys.argv[1]; os.makedirs(f'{out}/mra', exist_ok=True)
    for name, a in SETS.items():
        img = sim_rom(name, a)
        open(f'{out}/{name}.rom', 'wb').write(img)
        open(f'{out}/{name}.md5', 'w').write(hashlib.md5(img).hexdigest())
        open(f"{out}/mra/{a['title']} (Comad core).mra", 'w').write(mra(name, a))
        print(name, hex(len(img)), hashlib.md5(img).hexdigest())
