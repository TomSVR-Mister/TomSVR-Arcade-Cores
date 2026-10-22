#!/usr/bin/env python3
# gaelco2_build.py gaelco2.cpp zipdir outdir [sets] : JTGAELCO2 images + MRAs for MAME gaelco2.cpp sets.
# ROM layouts, DIP switches and game info are read from the MAME driver source (0.288, the version of Tom's zips);
# the zips are the user's own merged MAME zips, unmodified.
# Download layout (after the 8-byte header): 000000 68000 program (byte-swapped, padded to 1 MB) |
# 100000 graphics as 32-bit words: word a = bytes {plane1[a], plane0[a], plane3[a], plane2[a]} (byte 0 first),
# the layout of jlrh's Alligator Hunt MRA. Planes are 1/5 of MAME's "gfx" region each (the fifth is always empty).
# Header: byte 0 = log2(plane size / 0x80000); byte 1 = planes 2-3 read as zero from word (byte1 << 16) up
# (0 = never); byte 2 = sound bank map, 2 bits per bank (plane used by bank 0..3, from set_bank_offsets).
import sys, os, re, zipfile, hashlib

SETS = ['maniacsq', 'maniacsqc']
GFXA = 0x100000

src = open(sys.argv[1]).read()
zipdir, out = sys.argv[2], sys.argv[3]
os.makedirs(f'{out}/mra', exist_ok=True)

def num(s): return int(s, 0)

def rom_def(name):
    m = re.search(r'^ROM_START\(\s*%s\s*\)(.*?)^ROM_END' % re.escape(name), src, re.S | re.M)
    regions, cur = {}, None
    for line in m.group(1).splitlines():
        line = line.split('//')[0].strip()
        r = re.match(r'ROM_REGION\w*\(\s*(0x[0-9a-fA-F]+),\s*"([\w:]+)"', line)
        if r: cur = r.group(2); regions[cur] = dict(size=num(r.group(1)), roms=[]); continue
        l = re.match(r'(ROM_LOAD\w*)\(\s*"([^"]+)",\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+)\s*,.*?CRC\((\w+)\)', line)
        if l: regions[cur]['roms'].append(dict(kind=l.group(1), name=l.group(2), off=num(l.group(3)),
                                               len=num(l.group(4)), crc=l.group(5).lower()))
    return regions

def game_info(name):
    m = re.search(r'^GAME\(\s*(\d+),\s*%s,\s*(\w+),\s*(\w+),\s*(\w+),\s*\w+,\s*(\w+),\s*\w+,\s*"([^"]*)",\s*"([^"]*)"'
                  % re.escape(name), src, re.M)
    year, parent, machine, inp, init, manu, title = m.groups()
    return dict(year=year, parent=None if parent == '0' else parent, machine=machine, inp=inp, init=init,
                manu=manu, title=title)

def bank_offsets(machine):
    m = re.search(r'::%s\(machine_config &config\)\s*\{(.*?)^\}' % re.escape(machine), src, re.S | re.M)
    body = m.group(1)
    b = re.search(r'set_bank_offsets\((.*?)\);', body)
    if b: return [eval(x.strip()) for x in b.group(1).split(',')]
    base = re.match(r'\s*(\w+)\(config\);', body)          # derived machine: e.g. maniacsq_d5002fp
    return bank_offsets(base.group(1))

DEF = {'Off': 'Off', 'On': 'On', 'Demo_Sounds': 'Demo Sounds', 'Difficulty': 'Difficulty', 'Easy': 'Easy',
       'Normal': 'Normal', 'Hard': 'Hard', 'Hardest': 'Hardest', 'Unknown': 'Unknown', 'Free_Play': 'Free Play',
       'Coin_A': 'Coin A', 'Coin_B': 'Coin B', 'Lives': 'Lives', 'Unused': 'Unused'}

def label(s):
    s = s.strip()
    d = re.match(r'DEF_STR\(\s*(\w+)\s*\)', s)
    if d:
        k = d.group(1); c = re.match(r'(\d+)C_(\d+)C', k)
        return f'{c.group(1)}C/{c.group(2)}C' if c else DEF.get(k, k.replace('_', ' '))
    return s.strip('"').replace(',', ' ')

def ports(name):
    # DSW1 = IN0 high byte -> dipsw 7-0, DSW2 = IN1 high byte -> dipsw 15-8
    m = re.search(r'^static INPUT_PORTS_START\(\s*%s\s*\)(.*?)^INPUT_PORTS_END' % re.escape(name), src, re.S | re.M)
    dips, port, cur = {}, None, None
    for line in m.group(1).splitlines():
        line = line.split('//')[0].strip()
        p = re.match(r'PORT_(?:START|MODIFY)\(\s*"(\w+)"', line)
        if p: port = p.group(1); continue
        if port not in ('IN0', 'IN1'): continue
        sh = -8 if port == 'IN0' else 0
        f = (lambda v: v >> 8) if sh else (lambda v: v)
        d = re.match(r'PORT_DIPNAME\(\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+),\s*(.+?)\s*\)\s*(PORT_|$)', line)
        if d:
            mask = f(num(d.group(1)))
            cur = dict(name=label(d.group(3)), mask=mask, default=f(num(d.group(2))), settings={})
            dips[mask] = cur; continue
        s = re.match(r'PORT_DIPSETTING\(\s*(0x[0-9a-fA-F]+),\s*(.+?)\s*\)\s*$', line)
        if s and cur is not None: cur['settings'].setdefault(f(num(s.group(1))), label(s.group(2))); continue
        sv = re.match(r'PORT_SERVICE(?:_DIPLOC)?\(\s*(0x[0-9a-fA-F]+),\s*IP_ACTIVE_LOW', line)
        if sv:
            mask = f(num(sv.group(1)))
            dips[mask] = dict(name='Service Mode', mask=mask, default=mask, settings={0: 'On', mask: 'Off'}); cur = None
    return dips

def dip_lines(dips):
    lines, default = [], 0
    for mask in sorted(dips):
        d = dips[mask]; default |= d['default']
        bits = [b for b in range(16) if mask >> b & 1]
        ids = []
        for v in range(1 << len(bits)):
            val = sum(1 << bits[i] for i in range(len(bits)) if v >> i & 1)
            ids.append(d['settings'].get(val, '-'))
        lines.append(f'<dip name="{d["name"]}" bits="{",".join(map(str, bits))}" ids="{",".join(ids)}"/>')
    return lines, default

zcache = {}
def zipfiles(setname, parent):
    files = {}
    for z in [parent, setname] if parent else [setname]:
        p = f'{zipdir}/{z}.zip'
        if not os.path.exists(p): continue
        zf = zcache.setdefault(p, zipfile.ZipFile(p))
        for i in zf.infolist(): files['%08x' % i.CRC] = (zf, i)
    return files

def build(setname):
    g = game_info(setname); r = rom_def(setname)
    files = zipfiles(setname, g['parent'])
    prog, gfx = r['maincpu']['roms'], r['gfx']
    have = all(x['crc'] in files for x in prog + gfx['roms'])
    rd = lambda x: files[x['crc']][0].read(files[x['crc']][1])
    plane = gfx['size'] // 5
    psize = plane.bit_length() - 0x80000.bit_length()
    assert plane == 0x80000 << psize, setname
    # each plane = ROMs loaded inside it; planes 2-3 may be shorter (zero above)
    planes = [[x for x in gfx['roms'] if p * plane <= x['off'] < (p + 1) * plane] for p in range(4)]
    plen = [sum(x['len'] for x in pl) for pl in planes]
    hilim = 0 if plen[2] == plane and plen[3] == plane else max(plen[2], plen[3]) >> 16
    assert plen[0] == plane and plen[1] == plane and plen[2] == plen[3], (setname, plen)
    banks = bank_offsets(g['machine'])
    bmap = 0
    for i, o in enumerate(banks): bmap |= (o // plane) << (2 * i)
    hdr = bytes([psize, hilim, bmap, 0, 0, 0, 0, 0])

    P = lambda x, extra='': f'name="{x["name"]}" crc="{x["crc"]}"{extra}'
    ev = [x for x in prog if x['off'] % 2 == 0]; od = [x for x in prog if x['off'] % 2 == 1]
    assert len(ev) == 1 and len(od) == 1 and ev[0]['kind'] == 'ROM_LOAD16_BYTE'
    plen16 = ev[0]['len'] * 2
    parts = [f'        <part>{" ".join("%02X" % b for b in hdr)}</part>',
             '        <interleave output="16">', f'            <part {P(ev[0])} map="10"/>',
             f'            <part {P(od[0])} map="01"/>', '        </interleave>']
    if plen16 < GFXA: parts.append(f'        <part repeat="0x{GFXA - plen16:x}"> FF</part>')
    # graphics: plane p ROM byte -> output byte (1, 0, 3, 2)[p]
    MAP = ['0010', '0001', '1000', '0100']
    assert all(len(pl) == 1 for pl in planes), setname
    lo = plen[2]
    parts.append('        <interleave output="32">')
    for p in range(4):
        parts.append(f'            <part {P(planes[p][0], f" length=\"0x{lo:x}\"")} map="{MAP[p]}"/>')
    parts.append('        </interleave>')
    if lo < plane:   # planes 0-1 continue, planes 2-3 are cut by the core (hilim): fill with planes 0-1 again
        x = f' offset="0x{lo:x}" length="0x{plane - lo:x}"'
        parts += ['        <interleave output="32">',
                  f'            <part {P(planes[0][0], x)} map="0010"/>', f'            <part {P(planes[1][0], x)} map="0001"/>',
                  f'            <part {P(planes[0][0], x)} map="1000"/>', f'            <part {P(planes[1][0], x)} map="0100"/>',
                  '        </interleave>']
    if have:
        img = bytearray(hdr) + bytearray(b'\xff' * GFXA)
        e, o = rd(ev[0]), rd(od[0])
        for k in range(len(e)): img[8 + 2 * k] = o[k]; img[8 + 2 * k + 1] = e[k]
        pd = [rd(pl[0]) for pl in planes]
        g32 = bytearray(4 * plane)
        for a in range(plane):
            b0 = pd[1][a]; b1 = pd[0][a]
            b2 = pd[3][a] if a < lo else pd[1][a]; b3 = pd[2][a] if a < lo else pd[0][a]
            g32[4 * a:4 * a + 4] = bytes((b0, b1, b2, b3))
        img += g32
        md5 = hashlib.md5(img).hexdigest()
        open(f'{out}/{setname}.rom', 'wb').write(img); open(f'{out}/{setname}.md5', 'w').write(md5)
    else:
        md5 = 'None'
    dips, default = dip_lines(ports(g['inp']))
    title = g['title'].replace('&', '&amp;')
    zips = f'{setname}.zip|{g["parent"]}.zip' if g['parent'] else f'{setname}.zip'
    nl = '\n'
    mra = f'''<!-- {title} on JTGAELCO2, a personal MiSTer core for Gaelco 2 boards (MAME gaelco2.cpp "{setname}"),
     built on JTFRAME by Jose Tejada (jotego), with the Gaelco 2 video and GAE1 sound from jlrh's gaelco-fpga.
     The ROM is assembled from your own MAME zip, unmodified. Requires jtgaelco2.rbf. -->
<misterromdescription>
    <name>{title} (JTGAELCO2)</name>
    <setname>{setname}</setname>
    <rotation>horizontal</rotation>
    <mameversion>0288</mameversion>
    <year>{g["year"]}</year>
    <manufacturer>{g["manu"].replace("&", "&amp;")}</manufacturer>
    <players>2</players>
    <rbf>jtgaelco2</rbf>
    <joystick>8</joystick>
    <region>World</region>
    <rom index="0" zip="{zips}" md5="None">
{nl.join(parts)}
    </rom>
    <switches page_id="1" page_name="Switches" base="16" default="{default & 0xff:02x},{default >> 8:02x}">
{nl.join('        ' + d for d in dips)}
    </switches>
    <buttons names="Button 1,-,-,Start,Coin,Core credits" default="A,B,X,Start,Select,-" count="3"/>
</misterromdescription>
'''
    fn = re.sub(r'[/:]', '-', g['title'])
    open(f'{out}/mra/{fn} (JTGAELCO2).mra', 'w').write(mra)
    print(f'{setname:10} {"ok " if have else "no zip"} hdr {hdr[:3].hex()} {md5}')

for s in sys.argv[4:] or SETS: build(s)
