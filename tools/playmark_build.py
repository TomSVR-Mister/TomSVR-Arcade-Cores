#!/usr/bin/env python3
# playmark_build.py outdir : JTPLAYMARK images + MRAs for Big Twin / Excelsior (user's bigtwin.zip, excelsr.zip)
import sys, os, zipfile, hashlib
S = '/tmp/claude-0/-home-claude/183009bc-02e0-578a-b0ba-00b6083aaf64/scratchpad'
OKIA, BA1, BA2, PROM, HDR = 0x300000, 0x400000, 0x600000, 0x800000, 4

COIN = ['Free Play', '8C/3C', '5C/3C', '3C/2C', '2C/3C', '1C/6C', '1C/5C', '1C/4C', '1C/3C', '1C/2C', '6C/1C', '5C/1C', '4C/1C', '3C/1C', '2C/1C', '1C/1C']
DIPS_BT = [f'<dip name="Coinage" bits="1,2,3,4" ids="{",".join(COIN)}"/>', '<dip name="Credits to Start" bits="5" ids="2,1"/>',
           '<dip name="Language" bits="8" ids="English,Italian"/>', '<dip name="Censor Pictures" bits="10" ids="No,Yes"/>',
           '<dip name="Rising Ground Level" bits="11" ids="On,Off"/>', '<dip name="Difficulty" bits="12,13" ids="Hardest,Hard,Easy,Medium"/>',
           '<dip name="Allow Continue" bits="14" ids="No,Yes"/>', '<dip name="Demo Sounds" bits="15" ids="On,Off"/>']
DIPS_EX = [f'<dip name="Coinage" bits="1,2,3,4" ids="{",".join(COIN)}"/>', '<dip name="Credits to Start" bits="5" ids="2,1"/>',
           '<dip name="Percentage to Reveal" bits="6" ids="90%,80%"/>', '<dip name="Service Mode" bits="7" ids="On,Off"/>',
           '<dip name="Lives" bits="8,9" ids="1,4,2,3"/>', '<dip name="Censor Pictures" bits="10,11" ids="No,No,50%,100%"/>',
           '<dip name="Difficulty" bits="12,13" ids="Hard,Medium,Normal,Easy"/>', '<dip name="Allow Continue" bits="14" ids="No,Yes"/>',
           '<dip name="Demo Sounds" bits="15" ids="On,Off"/>']

GAMES = [
    dict(set='bigtwin', zip='bigtwin.zip', name='Big Twin', year=1995, exc=0,
         main=[(('2.302', 'e6767f60'), ('3.301', '5aba6990'))], oki=('1.013', 'ff6671dc'),
         hexf=('pic16c57-hs_bigtwin_015.hex', 'c07e9375'),
         spr=[('8.321', '2749644d'), ('9.322', '1d1897af'), ('10.323', '2a03432e'), ('11.324', '2c980c4c')],
         til=[('4.311', '6f628fbc'), ('5.312', '6a9b1752'), ('6.313', '411cf852'), ('7.314', '635c81fd')],
         dips=DIPS_BT, dsw='ff,7a', buttons=1),
    dict(set='excelsr', zip='excelsr.zip', name='Excelsior (set 1)', year=1996, exc=1,
         main=[(('19.u302', '9a8acddc'), ('22.u301', 'f0aa1c1b')), (('18.u304', 'fe517e0e'), ('21.u303', 'fdf9bd64')),
               (('17.u306', '978f9a6b'), ('20.u305', '8692afe9'))], oki=('16.i013', '7ed9da5d'),
         hexf=('pic16c57-hs_excelsior_i015.hex', '022c6941'),
         spr=[('24.u321', '17f46825'), ('28.u322', 'a823f2bd'), ('23.u323', 'd8e1453b'), ('27.u324', 'eca2c079')],
         til=[('26.u311', 'c171c059'), ('30.u312', 'b4a4c510'), ('25.u313', '667eec1b'), ('29.u314', '4acb0745')],
         dips=DIPS_EX, dsw='ff,63', buttons=3),
]
DIPS_HM = [f'<dip name="Coinage" bits="1,2,3,4" ids="{",".join(COIN)}"/>', '<dip name="Time Per Line" bits="6" ids="5 Seconds,10 Seconds"/>',
           '<dip name="Clear All Memory" bits="7" ids="On,Off"/>',
           '<dip name="Difficulty" bits="8,9,10" ids="Very Hard 5,Very Hard 4,Very Hard 3,Very Hard 2,Very Hard 1,Hard,Normal,Easy"/>',
           '<dip name="Service Mode" bits="11" ids="On,Off"/>', '<dip name="Demo Sounds" bits="12" ids="On,Off"/>',
           '<dip name="Token Dispenser" bits="13" ids="On,Off"/>', '<dip name="Ticket Dispenser" bits="14" ids="On,Off"/>',
           '<dip name="Clear Partial Memory" bits="15" ids="On,Off"/>']
HM = dict(zip='hotmind.zip', year=1995, exc=2, oki=('20.io13', '0bf3a3e5'), hexf=('hotmind_pic16c57.hex', '11957803'),
          spr=[('26.u86', 'ff8d3b75'), ('30.u85', '87a640c7'), ('25.u84', 'c4fd4445'), ('29.u83', '0bebfb53')],
          til=[('23.u36', 'ddcf60b9'), ('27.u42', '413bbcf4'), ('24.u39', '4baa5b4c'), ('28.u45', '8df34d6a')],
          dips=DIPS_HM, dsw='ff,8f', buttons=2)
GAMES.append(dict(HM, set='hotmind', name='Hot Mind (Hard Times hardware, set 1)', main=[(('21.u67', 'e9000f7f'), ('22.u66', '2c518ec5'))]))
GAMES.append(dict(HM, set='hotmindc', name='Hot Mind (Hard Times hardware, set 2)', main=[(('1.u67', '35b0f62d'), ('2.u66', '1a27033f'))]))
ex2 = dict(GAMES[1]); ex2.update(set='excelsra', name='Excelsior (set 2)',
    main=[(('19.u302', 'd13990a8'), ('22.u301', '55dca2da'))] + GAMES[1]['main'][1:])
GAMES.append(ex2)

DIPS_HT = [f'<dip name="Coinage" bits="1,2,3,4" ids="{",".join(COIN)}"/>', '<dip name="Credits to Start" bits="5" ids="2,1"/>',
           '<dip name="1 Life If Continue" bits="6" ids="Yes,No"/>', '<dip name="Service Mode" bits="7" ids="On,Off"/>',
           '<dip name="Lives" bits="8,9" ids="1,5,2,3"/>', '<dip name="Bonus Life" bits="10,11" ids="None,Only 500k,Every 500k,Every 300k-500k"/>',
           '<dip name="Difficulty" bits="12,13" ids="Very Hard,Hard,Easy,Normal"/>', '<dip name="Allow Continue" bits="14" ids="No,Yes"/>',
           '<dip name="Demo Sounds" bits="15" ids="On,Off"/>']
# Other Hard Times board games: header byte 0 = 2 | variant << 2 (1 Hard Times, 2 Lucky Boom, 3 Big Twin No Girls)
HT = dict(zip='hrdtimes.zip', year=1994, exc=6, board='Hard Times', oki=('30.io13', 'fa5e50ae'), pic=('pic16c57.bin', 'db307198'),
          dips=DIPS_HT, dsw='ff,7f', buttons=3)
GAMES.append(dict(HT, set='hrdtimes', name='Hard Times (set 1)', main=[(('31.u67', '53eb041b'), ('32.u66', 'f2c6b382'))],
                  spr=[('36.u86', 'f2fc1ca3'), ('40.u85', '368c15f4'), ('35.u84', '7bde46ec'), ('39.u83', 'a0bae586')],
                  til=[('33.u36', 'd1239ce5'), ('37.u42', 'aa692005'), ('34.u39', 'e4108c59'), ('38.u45', 'ff7cacf3')]))
GAMES.append(dict(HT, set='hrdtimesa', name='Hard Times (set 2)', main=[(('u67.bin', '3e1334cb'), ('u66.bin', '041ec30a'))],
                  spr=[('mh1_playmark_ht', '927e5989'), ('mh2_playmark_ht', 'e76f001b')],
                  til=[('fh1_playmark_ht', '3cca02b0'), ('fh2_playmark_ht', 'ed699acd')]))
GAMES.append(dict(set='luckboomh', zip='luckboom.zip', name='Lucky Boom (Hard Times hardware)', year=1996, exc=10, board='Hard Times',
                  main=[(('21.u67', '5578dd75'), ('22.u66', '1eb72a39'))], oki=('20.io13', '0d42c0a3'),
                  hexf=('luckyboom_pic16c57.hex', '5c4b5c39'),
                  spr=[('26.u86', 'd3ee7d82'), ('30.u85', '4b8a9558'), ('25.u84', 'e1ab5cf5'), ('29.u83', '9572d2d4')],
                  til=[('23.u36', '71840dd9'), ('27.u42', '2f86b37f'), ('24.u39', 'c6725797'), ('28.u40', '40e65ed1')],
                  dips=[], dsw='ff,ff', buttons=2, players=1))
GAMES.append(dict(GAMES[0], set='bigtwinb', name='Big Twin (No Girls Conversion)', exc=14, board='Hard Times',
                  main=[(('2.u67', 'f5cdf1a9'), ('3.u66', '084e990f'))],
                  til=[('4.u36', '99aaeacc'), ('5.u42', '5c1dfd72'), ('6.u39', '788f2df6'), ('7.u45', 'aedb2e6d')],
                  dips=[d for d in DIPS_BT if 'Censor' not in d], dsw='ff,7e'))

out = sys.argv[1]; os.makedirs(f'{out}/mra', exist_ok=True)
nl = '\n'
P = lambda f: f'name="{f[0]}" crc="{f[1]}"'
for g in GAMES:
    if not os.path.exists(f'{S}/userzips/{g["zip"]}'): print('skip', g['set'], '(no', g['zip'] + ')'); continue
    z = zipfile.ZipFile(f'{S}/userzips/{g["zip"]}'); by = {'%08x' % i.CRC: i for i in z.infolist()}
    rd = lambda f: z.read(by[f[1]])
    img = bytearray(PROM)
    parts = [f'        <part>{g["exc"]:02X} 00 00 00</part>']
    pos = 0
    for ev, od in g['main']:
        e, o = rd(ev), rd(od)
        for k in range(len(e)): img[pos+2*k+1] = e[k]; img[pos+2*k] = o[k]
        pos += 2*len(e)
        parts += ['        <interleave output="16">', f'            <part {P(ev)} map="10"/>', f'            <part {P(od)} map="01"/>', '        </interleave>']
    if pos < OKIA: parts.append(f'        <part repeat="0x{OKIA-pos:x}"> FF</part>'); img[pos:OKIA] = b'\xff' * (OKIA-pos)
    p = rd(g['oki']); img[OKIA:OKIA+len(p)] = p; parts.append(f'        <part {P(g["oki"])}/>')
    pos = OKIA + len(p)
    parts.append(f'        <part repeat="0x{BA1-pos:x}"> FF</part>'); img[pos:BA1] = b'\xff' * (BA1-pos)
    for base, files, end in ((BA1, g['spr'], BA2), (BA2, g['til'], PROM)):
        d = [rd(f) for f in files]
        if len(files) == 2:     # two 16-bit wide dumps: low half then high half of the planes
            n = len(d[0]) // 2
            for k in range(n):
                for q in range(4): img[base+4*k+q] = d[q//2][2*k+q%2]
            maps = ['0021', '2100']
        else:
            n = len(d[0])
            for k in range(n):
                for q in range(4): img[base+4*k+q] = d[q][k]
            maps = ["".join("1" if 3-i==q else "0" for i in range(4)) for q in range(4)]
        parts.append('        <interleave output="32">')
        for f, m in zip(files, maps): parts.append(f'            <part {P(f)} map="{m}"/>')
        parts.append('        </interleave>')
        pos = base + 4*n
        if pos < end: parts.append(f'        <part repeat="0x{end-pos:x}"> FF</part>'); img[pos:end] = b'\xff' * (end-pos)
    pf = g.get('hexf') or g['pic']
    h = rd(pf); parts.append(f'        <part {P(pf)}/>')
    full = bytes([g['exc'], 0, 0, 0]) + bytes(img) + h
    open(f'{out}/{g["set"]}.rom', 'wb').write(full)
    open(f'{out}/{g["set"]}.md5', 'w').write(hashlib.md5(full).hexdigest())
    # The core always has JTFRAME_BUTTONS=3: MiSTer maps the names list to joystick bits in order, so Start and Coin
    # must sit after three button slots whatever the game uses (with fewer, Select lands on a button or on Start).
    used = ['Button 1', 'Button 2', 'Button 3'][:g['buttons']]
    btn = ','.join(used + ['Unused'] * (3 - len(used)) + ['Start', 'Coin', 'Core credits'])
    bdef = 'A,B,X,Start,Select,-'
    sw = f'''    <switches page_id="1" page_name="Switches" base="16" default="{g["dsw"]}">
{nl.join('        ' + d for d in g["dips"])}
    </switches>
''' if g['dips'] else ''
    mra = f'''<!-- {g["name"]} on JTPLAYMARK, a personal MiSTer core for the Playmark {g.get("board") or ["Big Twin", "Excelsior", "Hard Times"][g["exc"]]} board (MAME playmark.cpp "{g["set"]}"),
     built on JTFRAME by Jose Tejada (jotego). The ROM is assembled from your own MAME zip, unmodified;
     the PIC16C57 sound program is MAME's {"HEX" if g.get("hexf") else "binary"} dump, decoded by the core. Requires jtplaymark.rbf. -->
<misterromdescription>
    <name>{g["name"]} (JTPLAYMARK)</name>
    <setname>{g["set"]}</setname>
    <rotation>horizontal</rotation>
    <mameversion>0264</mameversion>
    <year>{g["year"]}</year>
    <manufacturer>Playmark</manufacturer>
    <players>{g.get("players", 2)}</players>
    <rbf>jtplaymark</rbf>
    <joystick>8</joystick>
    <region>World</region>
    <rom index="0" zip="{g["zip"]}" md5="None">
{nl.join(parts)}
    </rom>
{sw}    <buttons names="{btn}" default="{bdef}" count="3"/>
</misterromdescription>
'''
    open(f'{out}/mra/{g["name"]} (JTPLAYMARK).mra', 'w').write(mra)
    print(g['set'], hashlib.md5(full).hexdigest(), len(full))
