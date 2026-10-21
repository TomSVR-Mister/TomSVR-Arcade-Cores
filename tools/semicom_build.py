#!/usr/bin/env python3
# semicom_build.py snowbros.cpp zipdir outdir : JTSEMICOM images + MRAs for the SemiCom sets of MAME snowbros.cpp.
# The ROM layouts, DIP switches and game info are read from the MAME driver source (0.264); the zips are the
# user's own MAME zips (merged sets: a clone is looked up in its own zip and in its parent's).
# Download layout (after the 4-byte header): 000000 68000 (byte-swapped) | 080000 Z80 | 0C0000 OKI | 100000 sprites
# (up to 2 MB) | 300000 PROM: protection data (0x200 bytes) | 302000 AT89C52 program (8 kB, MCU sets only).
# Header: byte 0 bits 1-0 = 0x200000 read (1 = 000a, 2 = 2a2a), bit 2 = protection data at 102000, bit 4 = MCU
# writes at 10e000 (Hyper Pacman); byte 1 = bg pen.
import sys, os, re, zipfile, hashlib

SETS = ['hyperpac', 'cookbib2', 'cookbib2a', 'toppyrap', 'cookbib2b', 'cookbib2c', 'cookbib3', 'pzlbreak', 'pzlbreaka', 'suhosong', 'twinkle', 'twinklea',
        '3in1semi', '3in1semia', 'mcheonru', 'moremore', 'moremorp', 'finalttr', 'hyperpacb']
SNDA, OKIA, GFXA, PROTA, MCUA, END = 0x80000, 0xC0000, 0x100000, 0x300000, 0x302000, 0x304000

src = open(sys.argv[1]).read()
zipdir, out = sys.argv[2], sys.argv[3]
os.makedirs(f'{out}/mra', exist_ok=True)

def num(s): return int(s, 0)

def rom_def(name):
    m = re.search(r'^ROM_START\(\s*%s\s*\)(.*?)^ROM_END' % re.escape(name), src, re.S | re.M)
    regions, cur = {}, None
    for line in m.group(1).splitlines():
        line = line.split('//')[0].strip()
        r = re.match(r'ROM_REGION(?:16_BE)?\(\s*(0x[0-9a-fA-F]+),\s*"(\w+)"', line)
        if r: cur = r.group(2); regions[cur] = []; continue
        l = re.match(r'(ROM_LOAD\w*)\(\s*"([^"]+)",\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+)\s*,.*?CRC\((\w+)\)', line)
        if l: regions[cur].append(dict(kind=l.group(1), name=l.group(2), off=num(l.group(3)), len=num(l.group(4)),
                                       crc=l.group(5).lower(), cont=[])); continue
        c = re.match(r'ROM_CONTINUE\(\s*(0x[0-9a-fA-F]+)\s*,\s*(0x[0-9a-fA-F]+)\)', line)
        if c: regions[cur][-1]['cont'].append((num(c.group(1)), num(c.group(2))))
    return regions

def game_info(name):
    m = re.search(r'^GAME\(\s*(\d+),\s*%s,\s*(\w+),\s*(\w+),\s*(\w+),\s*\w+,\s*(\w+),\s*\w+,\s*"([^"]*)",\s*"([^"]*)"'
                  % re.escape(name), src, re.M)
    year, parent, machine, inp, init, manu, title = m.groups()
    return dict(year=year, parent=None if parent == '0' else parent, machine=machine, inp=inp, init=init,
                manu=manu, title=title)

DEF = {'Off': 'Off', 'On': 'On', 'Demo_Sounds': 'Demo Sounds', 'Lives': 'Lives', 'Coinage': 'Coinage',
       'Difficulty': 'Difficulty', 'Easy': 'Easy', 'Normal': 'Normal', 'Hard': 'Hard', 'Hardest': 'Hardest',
       'Very_Hard': 'Very Hard', 'Free_Play': 'Free Play', 'Unknown': 'Unknown', 'Language': 'Language',
       'English': 'English', 'Korean': 'Korean', 'Bonus_Life': 'Bonus Life', 'None': 'None', 'Yes': 'Yes', 'No': 'No',
       'Unused': 'Unused', 'Flip_Screen': 'Flip Screen', 'Allow_Continue': 'Allow Continue', 'Very_Easy': 'Very Easy',
       'Medium': 'Medium', 'Game_Time': 'Game Time', 'Unlimited': 'Unlimited'}

def label(s):
    s = s.strip()
    d = re.match(r'DEF_STR\(\s*(\w+)\s*\)', s)
    if d:
        k = d.group(1); c = re.match(r'(\d+)C_(\d+)C', k)
        return f'{c.group(1)}C/{c.group(2)}C' if c else DEF.get(k, k.replace('_', ' '))
    return s.strip('"').replace(',', ' ')

def ports(name, dips=None):
    m = re.search(r'^static INPUT_PORTS_START\(\s*%s\s*\)(.*?)^INPUT_PORTS_END' % re.escape(name), src, re.S | re.M)
    dips = {} if dips is None else dips
    port, cur = None, None
    for line in m.group(1).splitlines():
        line = line.split('//')[0].strip()
        inc = re.match(r'PORT_INCLUDE\(\s*(\w+)\s*\)', line)
        if inc: ports(inc.group(1), dips); continue
        p = re.match(r'PORT_(?:START|MODIFY)\(\s*"(\w+)"', line)
        if p: port = p.group(1); continue
        if port not in ('DSW1', 'DSW2'): continue
        sh = 0 if port == 'DSW1' else 8
        d = re.match(r'PORT_DIPNAME\(\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+),\s*(.+?)\s*\)\s*(PORT_|$)', line)
        if d:
            mask = num(d.group(1)) << sh
            cur = dict(name=label(d.group(3)), mask=mask, default=num(d.group(2)) << sh, settings={})
            for k in [k for k in dips if k & mask]: del dips[k]
            dips[mask] = cur; continue
        s = re.match(r'PORT_DIPSETTING\(\s*(0x[0-9a-fA-F]+),\s*(.+?)\s*\)\s*$', line)
        if s and cur is not None: cur['settings'].setdefault(num(s.group(1)) << sh, label(s.group(2))); continue
        sv = re.match(r'PORT_SERVICE(?:_DIPLOC)?\(\s*(0x[0-9a-fA-F]+),\s*IP_ACTIVE_LOW', line)
        if sv:
            mask = num(sv.group(1)) << sh
            dips[mask] = dict(name='Service Mode', mask=mask, default=mask, settings={0: 'On', mask: 'Off'}); cur = None
            continue
        u = re.match(r'PORT_DIPUNUSED(?:_DIPLOC)?\(\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+)', line)
        if u:
            mask = num(u.group(1)) << sh
            dips[mask] = dict(name=None, mask=mask, default=num(u.group(2)) << sh, settings={}); cur = None
    return dips

def dip_lines(dips):
    lines, default = [], 0
    for mask in sorted(dips):
        d = dips[mask]; default |= d['default']
        if d['name'] is None: continue
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
    have = all(x['crc'] in files for reg in ('maincpu', 'soundcpu', 'oki', 'gfx1') for x in r[reg]) and \
           all(x['crc'] in files for x in r.get('user1', []) + r.get('protection', []))
    rd = lambda x: files[x['crc']][0].read(files[x['crc']][1])
    r200 = {'init_3in1semi': 1, 'init_cookbib3': 2}.get(g['init'], 0)
    pbase = 1 if g['machine'] == 'finalttr' else 0
    bgpen = 0xc0 if g['init'] == 'init_pzlbreak' else 0xf0
    mbase = 1 if g['init'] == 'init_hyperpac' else 0
    hdr = bytes([mbase << 4 | pbase << 3 | pbase << 2 | r200, bgpen, 0, 0])
    img = bytearray(hdr) + bytearray(END)
    P = lambda x, extra='': f'name="{x["name"]}" crc="{x["crc"]}"{extra}'
    parts = [f'        <part>{" ".join("%02X" % b for b in hdr)}</part>']
    pos = 0
    def pad(to, fill):
        nonlocal pos
        if to > pos: parts.append(f'        <part repeat="0x{to-pos:x}"> {fill:02X}</part>'); pos = to
    # 68000: even bytes (offset 0) and odd bytes (offset 1), byte-swapped into 16-bit words
    mc = r['maincpu']; ev = [x for x in mc if x['off'] == 0][0]; od = [x for x in mc if x['off'] == 1][0]
    parts += ['        <interleave output="16">', f'            <part {P(ev)} map="10"/>', f'            <part {P(od)} map="01"/>',
              '        </interleave>']
    if have:
        e, o = rd(ev), rd(od)
        for k in range(len(e)): img[4+2*k+1] = e[k]; img[4+2*k] = o[k]
    pos = 2 * ev['len']
    pad(SNDA, 0)
    # Z80 (cookbib3: 16 kB pieces in reverse order)
    s = r['soundcpu'][0]
    if s['cont']:
        pieces = sorted([(s['off'], 0, s['len'])] + [(a, (k+1)*s['len'], l) for k, (a, l) in enumerate(s['cont'])])
        for a, fo, l in pieces:
            parts.append(f'        <part {P(s, f" offset=\"0x{fo:x}\" length=\"0x{l:x}\"")}/>')
            if have: img[4+SNDA+a:4+SNDA+a+l] = rd(s)[fo:fo+l]
        pos = SNDA + sum(p[2] for p in pieces)
    else:
        parts.append(f'        <part {P(s)}/>')
        if have: img[4+SNDA:4+SNDA+s['len']] = rd(s)
        pos = SNDA + s['len']
    pad(OKIA, 0)
    o = r['oki'][0]; parts.append(f'        <part {P(o)}/>')
    if have: img[4+OKIA:4+OKIA+o['len']] = rd(o)
    pos = OKIA + o['len']
    pad(GFXA, 0xff)
    for x in sorted(r['gfx1'], key=lambda x: x['off']):
        pad(GFXA + x['off'], 0xff)
        parts.append(f'        <part {P(x)}/>')
        if have: img[4+GFXA+x['off']:4+GFXA+x['off']+x['len']] = rd(x)
        pos = GFXA + x['off'] + x['len']
    pad(PROTA, 0xff)
    for i in range(GFXA + sum(x['len'] for x in r['gfx1']), PROTA): img[4+i] = 0xff
    for i in range(OKIA + o['len'], GFXA): img[4+i] = 0xff
    pr = r.get('user1', [])
    if pr:
        parts.append(f'        <part {P(pr[0])}/>')
        if have: img[4+PROTA:4+PROTA+0x200] = rd(pr[0])
    else:
        parts.append(f'        <part repeat="0x200"> 00</part>')
    mcu = r.get('protection', [])
    if mcu:
        parts.append(f'        <part repeat="0x{MCUA-PROTA-0x200:x}"> 00</part>')
        parts.append(f'        <part {P(mcu[0])}/>')
        if have: img[4+MCUA:4+MCUA+mcu[0]['len']] = rd(mcu[0])
    dips, _ = dip_lines(ports(g['inp']))
    _, default = dip_lines(ports(g['inp']))
    md5 = hashlib.md5(img).hexdigest() if have else 'None'
    if have:
        open(f'{out}/{setname}.rom', 'wb').write(img); open(f'{out}/{setname}.md5', 'w').write(md5)
    title = g['title'].replace('&', '&amp;')
    zips = f'{setname}.zip|{g["parent"]}.zip' if g['parent'] else f'{setname}.zip'
    nl = '\n'
    mra = f'''<!-- {title} on JTSEMICOM, a personal MiSTer core for the SemiCom games on the Snow Bros-style board
     (MAME snowbros.cpp "{setname}"), built on JTFRAME by Jose Tejada (jotego). The ROM is assembled from your own
     MAME zip, unmodified. Requires jtsemicom.rbf. -->
<misterromdescription>
    <name>{title} (JTSEMICOM)</name>
    <setname>{setname}</setname>
    <rotation>horizontal</rotation>
    <mameversion>0264</mameversion>
    <year>{g["year"]}</year>
    <manufacturer>{g["manu"].replace("&", "&amp;")}</manufacturer>
    <players>2</players>
    <rbf>jtsemicom</rbf>
    <joystick>8</joystick>
    <region>World</region>
    <rom index="0" zip="{zips}" md5="None">
{nl.join(parts)}
    </rom>
    <switches page_id="1" page_name="Switches" base="16" default="{default & 0xff:02x},{default >> 8:02x}">
{nl.join('        ' + d for d in dips)}
    </switches>
    <buttons names="Button 1,Button 2,Button 3,Start,Coin,Core credits" default="A,B,X,Start,Select,-" count="3"/>
</misterromdescription>
'''
    fn = re.sub(r'[/:]', '-', g['title'])
    open(f'{out}/mra/{fn} (JTSEMICOM).mra', 'w').write(mra)
    print(f'{setname:10} {"ok " if have else "no zip"} {md5}')

for s in sys.argv[4:] or SETS: build(s)
