#!/usr/bin/env python3
# gaelco2_build.py gaelco2.cpp zipdir outdir [sets] : JTGAELCO2 images + MRAs for MAME gaelco2.cpp sets.
# ROM layouts, DIP switches and game info are read from the MAME driver source (0.288, the version of Tom's zips);
# the zips are the user's own merged MAME zips, unmodified.
# Download layout (after the 8-byte header): 000000 68000 program (byte-swapped, padded to 1 MB) |
# 100000 graphics as 32-bit words: word a = bytes {plane1[a], plane0[a], plane3[a], plane2[a]} (byte 0 first),
# the layout of jlrh's Alligator Hunt MRA. Planes are 1/5 of MAME's "gfx" region each (the fifth is always empty).
# Header: byte 0 = log2(plane size / 0x80000); byte 1 = planes 2-3 read as zero from word (byte1 << 16) up
# (0 = never); byte 2 = sound bank map, 2 bits per bank (plane used by bank 0..3, from set_bank_offsets);
# byte 3 bit 0 = DS5002FP present, its 32 kB SRAM image at download offset 0x900000 (PROM).
import sys, os, re, zipfile, hashlib

SETS = ['maniacsq', 'maniacsqc', 'maniacsqa', 'maniacsqb', 'maniacsqs', 'snowboar', 'snowboara',
        'bang', 'banga', 'bangb', 'bangj', 'bangja', 'bangjb',
        'touchgo', 'touchgoa', 'touchgona', 'touchgonna', 'touchgonnaa', 'touchgonnab', 'touchgonnac', 'touchgoun']
GFXA, P4A, PROMA = 0x100000, 0x1100000, 0x1500000

src = open(sys.argv[1]).read()
src_m = open(os.path.join(os.path.dirname(sys.argv[1]), 'gaelco2_m.cpp')).read()
zipdir, out = sys.argv[2], sys.argv[3]
os.makedirs(f'{out}/mra', exist_ok=True)

def num(s): return int(s, 0)

def rom_def(name):
    m = re.search(r'^ROM_START\(\s*%s\s*\)(.*?)^ROM_END' % re.escape(name), src, re.S | re.M)
    regions, cur = {}, None
    for line in m.group(1).splitlines():
        line = line.split('//')[0].strip()
        r = re.match(r'ROM_REGION\w*\(\s*(0x[0-9a-fA-F]+),\s*"([\w:]+)"', line)
        if r: cur = r.group(2); regions[cur] = dict(size=num(r.group(1)), roms=[], fills=[]); continue
        f = re.match(r'ROM_FILL\(\s*(0x[0-9a-fA-F]+),\s*(\w+),\s*(0x[0-9a-fA-F]+)\s*\)', line)
        if f and cur: regions[cur]['fills'].append((num(f.group(1)), num(f.group(2)), num(f.group(3))))
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

def machine_cfg(machine):
    m = re.search(r'::%s\(machine_config &config\)\s*\{(.*?)^\}' % re.escape(machine), src, re.S | re.M)
    body = m.group(1)
    vis = re.search(r'set_visarea\(0,\s*(\d+)-1', body)
    base = re.match(r'\s*(\w+)\(config\);', body)
    if not vis and base: return machine_cfg(base.group(1))
    clk = re.search(r'M68000\(config, m_maincpu, XTAL\((\d+)\'(\d+)\'(\d+)\)\s*/\s*(\d+)\)', body)
    mhz = int(clk.group(1)) / int(clk.group(4)) if clk else 12
    return dict(wide=1 if vis and int(vis.group(1)) == 384 else 0,
                snow=1 if ('snowboar_map' in body or 'bang_map' in body) else 0, fast=1 if mhz == 15 else 0,
                bang=1 if 'bang_map' in body else 0, tg=1 if 'touchgo_map' in body else 0)

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
        s = re.match(r'PORT_DIPSETTING\(\s*(0x[0-9a-fA-F]+),\s*("[^"]*"|DEF_STR\(\s*\w+\s*\))', line)
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
    pfills = r['maincpu']['fills']
    mcu = r.get('gaelco_ds5002fp:sram', {}).get('roms', [])
    scratch = r.get('gaelco_ds5002fp:mcu:internal', {}).get('roms', [])   # Touch and Go: internal RAM image
    # ROMs in "gfx_temp" are split by the driver init (ROM16_split_gfx): even bytes to dest1, odd to dest2
    if 'gfx_temp' in r:
        fn = re.search(r'::%s\(\)\s*\{(.*?)^\}' % re.escape(g['init']), src_m, re.S | re.M).group(1)
        for c in re.finditer(r'ROM16_split_gfx\("gfx_temp",\s*"gfx",\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+)\)', fn):
            st, ln, d1, d2 = (num(c.group(i)) for i in range(1, 5))
            l16 = [x for x in r['gfx_temp']['roms'] if x['kind'] == 'ROM_LOAD16_BYTE' and st <= x['off'] < st + ln]
            if l16:   # byte-wide ROM pairs (touchgona): even files go whole to dest1, odd files to dest2
                for x in l16:
                    o = x['off'] - st
                    gfx['roms'].append(dict(x, kind='ROM_LOAD', off=(d2 if o % 2 else d1) + o // 2))
                continue
            x = next(x for x in r['gfx_temp']['roms'] if x['off'] <= st < x['off'] + x['len'])
            for half, d in ((0, d1), (1, d2)):
                gfx['roms'].append(dict(x, kind='split', off=d, len=ln // 2, sofs=st - x['off'], half=half))
        gfx['roms'] = [x for x in gfx['roms'] if x['crc'] != '00000000']
    have = all(x['crc'] in files for x in prog + gfx['roms'] + mcu + scratch)
    def rdp(x):   # bytes of a gfx entry (split entries: every other byte of their ROM)
        d = rd(x)
        return d[x['sofs'] + x['half']::2][:x['len']] if x['kind'] == 'split' else d
    rd = lambda x: files[x['crc']][0].read(files[x['crc']][1])
    plane = gfx['size'] // 5
    psize = plane.bit_length() - 0x80000.bit_length()
    assert plane == 0x80000 << psize, setname
    # each plane = ROMs loaded inside it, in order; a plane may end early (MAME ROM_FILL zeros): the core zeroes
    # planes 0-1 / 2-3 / 4 above lolim / hilim / p4lim, so the MRA may put any data there
    planes = [sorted([x for x in gfx['roms'] if p * plane <= x['off'] < (p + 1) * plane], key=lambda x: x['off'])
              for p in range(5)]
    for p in range(5):   # ROMs contiguous from the plane start
        o = p * plane
        for x in planes[p]: assert x['off'] == o, (setname, p, x['name']); o += x['len']
    plen = [sum(x['len'] for x in pl) for pl in planes]
    assert plen[0] == plen[1] and plen[2] == plen[3], (setname, plen)
    lim = lambda n: 0 if n >= plane else n >> 16
    lolim, hilim, p4lim = lim(plen[0]), lim(plen[2]), lim(plen[4])
    bpp5 = plen[4] > 0
    m = machine_cfg(g['machine'])
    snow, wide = m['snow'], m['wide']
    banks = bank_offsets(g['machine'])
    bmap = 0
    for i, o in enumerate(banks): bmap |= (o // plane) << (2 * i)
    hdr = bytes([psize, hilim, bmap, (1 if mcu else 0) | snow << 1 | wide << 2 | bpp5 << 3 | m['fast'] << 4 | m['bang'] << 5 | m['tg'] << 6, lolim, p4lim, 0, 0])

    P = lambda x, extra='': f'name="{x["name"]}" crc="{x["crc"]}"{extra}'
    ev = [x for x in prog if x['off'] % 2 == 0]; od = [x for x in prog if x['off'] % 2 == 1]
    assert len(ev) == 1 and len(od) == 1 and ev[0]['kind'] == 'ROM_LOAD16_BYTE'
    plen16 = ev[0]['len'] * 2
    parts = [f'        <part>{" ".join("%02X" % b for b in hdr)}</part>',
             '        <interleave output="16">', f'            <part {P(ev[0])} map="10"/>',
             f'            <part {P(od[0])} map="01"/>', '        </interleave>']
    if plen16 < GFXA: parts.append(f'        <part repeat="0x{GFXA - plen16:x}"> FF</part>')
    # graphics as 32-bit words: plane p ROM byte -> output byte (1, 0, 3, 2)[p]. Cut the planes into chunks where
    # no plane changes ROM; where a plane has no ROM, repeat another plane's bytes (the core zeroes them).
    MAP = ['0010', '0001', '1000', '0100']
    def at(p, a):        # (rom, offset in rom) holding plane p byte a, or None
        for x in planes[p]:
            if x['off'] - p * plane <= a < x['off'] - p * plane + x['len']: return x, a - (x['off'] - p * plane)
        return None
    cuts = sorted({0, plane} | {x['off'] - p * plane for p in range(4) for x in planes[p]} |
                  {x['off'] - p * plane + x['len'] for p in range(4) for x in planes[p]})
    step = min(x['len'] for p in range(4) for x in planes[p])
    cuts = sorted(set(c for c in cuts if c <= plane) | set(range(0, plane + 1, step)))
    PAIRMAP = {(0, 1): '0012', (2, 3): '1200'}
    def src(p, a): return at(p, a) or at(p ^ 2, a) or at(0, a % plen[0])
    def srcpair(pair, a):   # ROM bytes for both planes of a pair
        (x0, o0), (x1, o1) = src(pair[0], a), src(pair[1], a)
        ok = not (x0['kind'] == 'split' or x1['kind'] == 'split') or \
             (x0['name'] == x1['name'] and x0['half'] == 0 and x1['half'] == 1 and o0 == o1)
        if ok: return (x0, o0), (x1, o1)
        # filler where a split pair has no ROM (Touch and Go planes 0-1 end at 3 MB): copy a whole pair
        q = (pair[0] ^ 2, pair[1] ^ 2)
        if at(q[0], a) and at(q[1], a): return at(q[0], a), at(q[1], a)
        return at(0, a % plen[0]), at(1, a % plen[0])
    for a, b in zip(cuts, cuts[1:]):
        parts.append('        <interleave output="32">')
        for pair in ((0, 1), (2, 3)):
            (x0, o0), (x1, o1) = srcpair(pair, a)
            if x0['kind'] == 'split' or x1['kind'] == 'split':
                # both planes must be the two halves of one split ROM: one 16-bit part
                assert x0['name'] == x1['name'] and x0['half'] == 0 and x1['half'] == 1 and o0 == o1, (setname, a)
                so = x0['sofs'] + 2 * o0
                ex = (f' offset="0x{so:x}"' if so else '') + f' length="0x{2 * (b - a):x}"'
                parts.append(f'            <part {P(x0, ex)} map="{PAIRMAP[pair]}"/>')
                continue
            for p, (x, off) in zip(pair, ((x0, o0), (x1, o1))):
                ex = (f' offset="0x{off:x}"' if off else '') + (f' length="0x{b - a:x}"' if b - a != x['len'] else '')
                parts.append(f'            <part {P(x, ex)} map="{MAP[p]}"/>')
        parts.append('        </interleave>')
    gend = GFXA + 4 * plane
    if bpp5:   # plane 5 starts at P4A (BA2_START); pad the gap after planes 1-4 (none when the plane is 4 MB)
        if gend < P4A: parts.append(f'        <part repeat="0x{P4A - gend:x}"> 00</part>')
        for x in planes[4]: parts.append(f'        <part {P(x)}/>')
        if plen[4] < plane: parts.append(f'        <part repeat="0x{plane - plen[4]:x}"> 00</part>')
        gend = P4A + plane
    if mcu:
        assert len(mcu) == 1 and mcu[0]['len'] == 0x8000 and gend <= PROMA
        if gend < PROMA: parts.append(f'        <part repeat="0x{PROMA - gend:x}"> 00</part>')
        parts.append(f'        <part {P(mcu[0])}/>')
        if scratch: parts.append(f'        <part {P(scratch[0])}/>')   # PROM offset 0x8000
    if have:
        img = bytearray(hdr) + bytearray(b'\xff' * GFXA)
        e, o = rd(ev[0]), rd(od[0])
        for k in range(len(e)): img[8 + 2 * k] = o[k]; img[8 + 2 * k + 1] = e[k]
        for a, n, v in pfills:
            for k in range(n): img[8 + ((a + k) ^ 1)] = v
        pdata = []
        for p in range(4):
            d = bytearray(plane)
            for x in planes[p]: d[x['off'] - p * plane:x['off'] - p * plane + x['len']] = rdp(x)
            pdata.append(d)
        # bytes of planes without ROM: the same substitute data the MRA uses
        for a, b in zip(cuts, cuts[1:]):
            for pair in ((0, 1), (2, 3)):
                for p, (x, off) in zip(pair, srcpair(pair, a)):
                    if at(p, a) is None: r = rdp(x); pdata[p][a:b] = r[off:off + b - a]
        g32 = bytearray(4 * plane)
        g32[0::4] = pdata[1]; g32[1::4] = pdata[0]; g32[2::4] = pdata[3]; g32[3::4] = pdata[2]
        img += g32
        if bpp5:
            p4 = b''.join(rdp(x) for x in planes[4]); img += bytes(P4A - (GFXA + 4 * plane)) + p4 + bytes(plane - len(p4))
        if mcu: img += bytes(PROMA - gend) + rd(mcu[0]); open(f'{out}/{setname}_mcu.bin', 'wb').write(rd(mcu[0]))
        if scratch: img += rd(scratch[0])
        md5 = hashlib.md5(img).hexdigest()
        open(f'{out}/{setname}.rom', 'wb').write(img); open(f'{out}/{setname}.md5', 'w').write(md5)
    else:
        md5 = 'None'
    dips, default = dip_lines(ports(g['inp']))
    title = g['title'].replace('&', '&amp;')
    # boards with an EEPROM (Snow Board) have no DIP switches: settings are in the game's service menu
    switches = (f'    <switches page_id="1" page_name="Switches" base="16" default="{default & 0xff:02x},{default >> 8:02x}">\n'
                + ''.join('        ' + d + '\n' for d in dips) + '    </switches>\n') if dips else ''
    bnames = 'Rotate,Button 2,Button 3' if setname.startswith('maniacsq') else 'Fire,-,-' if m['bang'] else 'Button 1,Button 2,Button 3'
    bnames = bnames.replace('Fire,-,-', 'Fire,Button 2,Button 3')
    # light gun games: core_mod bit 1 makes JTFRAME draw a crosshair (mouse, analog stick, d-pad or Sinden)
    coremod = '    <rom index="1"><part>02 00</part></rom>\n' if m['bang'] else ''
    # program ROM_FILLs (touchgona: byte 1 of the stack pointer); program byte a sits at image offset 8 + (a ^ 1)
    patches = ''.join(f'        <patch offset="0x{8 + ((a + k) ^ 1):x}">{v:02X}</patch>\n'
                      for a, n, v in pfills for k in range(n))
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
    <players>{4 if m['tg'] else 2}</players>
    <rbf>jtgaelco2</rbf>
    <joystick>8</joystick>
    <region>World</region>
    <rom index="0" zip="{zips}" md5="None">
{nl.join(parts)}
{patches}    </rom>
{coremod}{switches}    <buttons names="{bnames},Start,Coin,Core credits" default="A,B,X,Start,Select,-" count="3"/>
</misterromdescription>
'''
    fn = re.sub(r'[/:]', '-', g['title'])
    open(f'{out}/mra/{fn} (JTGAELCO2).mra', 'w').write(mra)
    print(f'{setname:10} {"ok " if have else "no zip"} hdr {hdr[:6].hex()} {md5}')

for s in sys.argv[4:] or SETS: build(s)
