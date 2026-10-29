#!/usr/bin/env python3
"""Make the TomSVR Leland sports pack MRAs (rbf TomSVR_leland) from MAME 0.264 leland.cpp.

Usage: leland_build.py <leland.cpp> <out dir> [rbf name]

The SDRAM image is the MAME regions placed at the core's fixed bases (lc1/rtl/leland_board_pkg.sv):
  GEN3 (Viper, Team QB, AAFB): master 0x000000, slave 0x100000, 80186 0x300000, bg_gfx 0x400000
    (3 planes at a 0x8000 stride; 0x4000 planes are mirrored, MAME wraps tile codes the same way),
    bg_prom 0x600000, eeprom 0x700000.
  GEN4 WSF (World Soccer Finals): laid out like the official Indy Heat MRA (master code, XROM
    byte-interleaved at 0x80000, slave, ext DAC at 0x280000, gfx planes byte-interleaved into rows).
"""
import re, sys, os

GEN3, GEN4_WSF = 3, 5
# setname: (game_id, board_class, input_scheme, flags, buttons, defaults, players text)
VB = 0x80  # FLAG_VIPER_BANK
SETS = {
    'viper':   (6,  GEN3, 7,  VB, 'Fire,Bomb,Start,Coin', 'A,B,Start,Select'),
    'teamqb':  (7,  GEN3, 8,  VB, 'Pass,Start,Coin', 'A,Start,Select'),
    'teamqb2': (7,  GEN3, 8,  VB, 'Pass,Start,Coin', 'A,Start,Select'),
    'aafb':    (8,  GEN3, 8,  VB, 'Pass,Start,Coin', 'A,Start,Select'),
    'aafbc':   (9,  GEN3, 8,  VB, 'Pass,Start,Coin', 'A,Start,Select'),
    'aafbd2p': (10, GEN3, 9,  VB, 'Pass,Start,Coin', 'A,Start,Select'),
    'quarterb':  (12, GEN3, 8, VB, 'Pass,Start,Coin', 'A,Start,Select'),
    'quarterba': (12, GEN3, 8, VB, 'Pass,Start,Coin', 'A,Start,Select'),
    'quarterbc': (12, GEN3, 8, VB, 'Pass,Start,Coin', 'A,Start,Select'),
    'wsf':     (11, GEN4_WSF, 10, 0x2E, 'Kick,Pass,Start,Coin', 'A,B,Start,Select'),
    'wsf3':    (11, GEN4_WSF, 10, 0x2E, 'Kick,Pass,Start,Coin', 'A,B,Start,Select'),
}
CATEGORY = {'viper': 'Shooter', 'wsf': 'Sports', 'wsf3': 'Sports'}
ROT = {'ROT0': 'horizontal', 'ROT270': 'vertical (ccw)', 'ROT90': 'vertical (cw)'}


def parse(src):
    games, roms = {}, {}
    for m in re.finditer(r'^GAME\(\s*(\d+),\s*(\w+),\s*(\w+),\s*\w+,\s*\w+,\s*\w+,\s*\w+,\s*(\w+),\s*"([^"]*)",\s*"([^"]*)"', src, re.M):
        year, name, parent, rot, manu, title = m.groups()
        games[name] = dict(year=year, parent=None if parent == '0' else parent, rot=rot, manu=manu, title=title)
    for m in re.finditer(r'ROM_START\( (\w+) \)(.*?)ROM_END', src, re.S):
        regions, cur, last = {}, None, None
        for line in m.group(2).splitlines():
            line = line.split('//')[0].strip()
            r = re.match(r'ROM_REGION(?:16_BE)?\(\s*(0x[0-9a-f]+),\s*"([^"]+)"', line, re.I)
            if r:
                cur = regions.setdefault(r.group(2), [])
                continue
            r = re.match(r'(ROM_LOAD16_BYTE|ROM_LOAD16_WORD|ROM_LOAD)\(\s*"([^"]+)",\s*(0x[0-9a-f]+),\s*(0x[0-9a-f]+),\s*CRC\((\w+)\)', line, re.I)
            if r:
                kind, name, off, ln, crc = r.groups()
                last = dict(kind=kind, name=name, crc=crc.lower(), flen=int(ln, 16), fofs=0)
                cur.append(dict(last, off=int(off, 16), len=int(ln, 16)))
                continue
            r = re.match(r'ROM_(RELOAD|CONTINUE)\(\s*(0x[0-9a-f]+),\s*(0x[0-9a-f]+)', line, re.I)
            if r:
                kind, off, ln = r.groups()
                ln = int(ln, 16)
                if kind == 'CONTINUE':
                    prev = [e for e in cur if e['name'] == last['name']]
                    fofs = sum(e['len'] for e in prev)
                    last['flen'] += ln
                    for e in prev:
                        e['flen'] = last['flen']
                    cur.append(dict(last, off=int(off, 16), len=ln, fofs=fofs))
                else:
                    cur.append(dict(last, off=int(off, 16), len=ln, fofs=0))
        roms[m.group(1)] = regions
    return games, roms


def part(e, fofs=None, ln=None, mp=None):
    fofs = e['fofs'] if fofs is None else fofs
    ln = e['len'] if ln is None else ln
    a = f'<part name="{e["name"]}" crc="{e["crc"]}"'
    if fofs or ln != e['flen']:
        a += f' offset="0x{fofs:X}"'
    a += f' length="0x{ln:X}"'
    if mp:
        a += f' map="{mp}"'
    return a + '/>'


def pad(n):
    return [f'<part repeat="0x{n:X}">00</part>'] if n > 0 else []


def region(entries, size):
    """Raw MAME region as parts, padded to size. LOAD16_BYTE pairs become 16-bit interleaves."""
    chunks = []
    byte16 = [e for e in entries if e['kind'] == 'ROM_LOAD16_BYTE']
    used = set()
    for e in byte16:
        if e['off'] & 1 or id(e) in used:
            continue
        odd = next(o for o in byte16 if o['off'] == e['off'] + 1 and o['len'] == e['len'])
        used |= {id(e), id(odd)}
        chunks.append((e['off'], 2 * e['len'], ['<interleave output="16">', '\t' + part(e, mp='01'),
                                               '\t' + part(odd, mp='10'), '</interleave>']))
    for e in entries:
        if e['kind'] != 'ROM_LOAD16_BYTE':
            chunks.append((e['off'], e['len'], [part(e)]))
    chunks.sort(key=lambda c: c[0])
    out, pos = [], 0
    for off, ln, xml in chunks:
        assert off >= pos, (off, pos)
        out += pad(off - pos) + xml
        pos = off + ln
    assert pos <= size, (pos, size)
    return out + pad(size - pos)


def gen3(r):
    out = region(r['master'], 0x100000) + region(r['slave'], 0x200000) + region(r['custom:audiocpu'], 0x100000)
    gfx = r['bg_gfx']
    plane = sum(e['len'] for e in gfx) // 3
    assert plane in (0x4000, 0x8000) and all(e['len'] == plane for e in gfx), gfx
    for e in gfx:
        out += [part(e)] * (0x8000 // plane)
    out += pad(0x200000 - 0x18000)
    out += region(r['bg_prom'], 0x100000)
    out += [part(r['eeprom'][0])]
    return out


def wsf(r):
    m = r['master']
    seen, code_roms = set(), []                                     # code ROMs in order, no RELOADs
    for e in m:
        if e['name'] not in seen:
            seen.add(e['name'])
            code_roms.append(e)
    out = [part(e) for e in code_roms]
    code = sum(e['len'] for e in code_roms)
    out += pad(0x80000 - code)
    x = r['xrom']                                                    # XROM1 even/odd = u68/u69
    assert len(x) == 2 and x[0]['len'] == x[1]['len'] == 0x10000, x
    out += ['<interleave output="16">', '\t' + part(x[0], mp='01'), '\t' + part(x[1], mp='10'), '</interleave>']
    out += pad(0x80000 - 0x20000)
    s = r['slave']
    out += [part(e) for e in s]
    out += pad(0x180000 - sum(e['len'] for e in s))
    ext = r['custom:ext']
    out += [part(e) for e in ext] + pad(0x80000 - sum(e['len'] for e in ext))
    out += region(r['custom:audiocpu'], 0x100000)
    g = r['bg_gfx']
    assert len(g) == 6
    out += ['<interleave output="64">'] + ['\t' + part(e, mp=''.join('1' if b == i else '0' for b in range(7, -1, -1)))
                                         for i, e in enumerate(g + [g[0], g[0]])] + ['</interleave>']
    out += pad(0x300000 - 8 * g[0]['len'])
    out += [part(r['eeprom'][0])]
    return out


def mra(name, g, r, rbf):
    gid, bc, scheme, flags, buttons, defaults = SETS[name]
    zips = f'{name}.zip' + (f'|{g["parent"]}.zip' if g['parent'] else '')
    hdr = ' '.join(f'{b:02X}' for b in [0x4C, 0x01, bc, gid, scheme, flags] + [0] * 10)
    body = gen3(r) if bc == GEN3 else wsf(r)
    nv = 256 if bc == GEN4_WSF else 128
    four = scheme == 10 or (scheme == 8 and gid != 12)
    note = {
        7: 'Trackball: analog stick, D-pad, spinner or mouse.',
        8: ('Two players. ' if gid == 12 else 'Four players (controllers 1-4). ') + 'Pass/aim with the analog stick or D-pad.',
        9: 'Two players. Pass/aim with the analog stick or D-pad.',
        10: 'Four players (controllers 1-4).',
    }[scheme]
    title = g['title']
    lines = ['<misterromdescription>',
             f'\t<name>{title} [TomSVR]</name>',
             '\t<mameversion>0264</mameversion>',
             f'\t<setname>{name}</setname>']
    if g['parent']:
        lines.append(f'\t<parent>{g["parent"]}</parent>')
    lines += [f'\t<year>{g["year"]}</year>',
              f'\t<manufacturer>{g["manu"]}</manufacturer>',
              f'\t<category>{CATEGORY.get(name, "Sports")}</category>',
              f'\t<rbf>{rbf}</rbf>',
              f'\t<rotation>{ROT[g["rot"]]}</rotation>',
              f'\t<rom index="0" address="0x30000000" zip="{zips}" md5="None" type="merged">',
              f'\t\t<part>{hdr}</part>']
    ind = 2
    for l in body:
        if l.startswith('</interleave'):
            ind -= 1
        lines.append('\t' * ind + l.lstrip('\t'))
        if l.startswith('<interleave'):
            ind += 1
    lines += ['\t</rom>',
              f'\t<!-- {note} Coin = Select, Start = Start. Operator menu: OSD "Service Menu". -->',
              f'\t<buttons names="{buttons}" default="{defaults}" count="{4 if four else 2}"/>',
              f'\t<nvram index="4" size="{nv}"/>',
              '</misterromdescription>', '']
    return f'{title} [TomSVR].mra'.replace(':', ' -').replace('/', '-'), '\n'.join(lines)


def main():
    src = open(sys.argv[1]).read()
    out = sys.argv[2]
    rbf = sys.argv[3] if len(sys.argv) > 3 else 'TomSVR_leland'
    games, roms = parse(src)
    os.makedirs(out, exist_ok=True)
    for name in SETS:
        fn, text = mra(name, games[name], roms[name], rbf)
        open(os.path.join(out, fn), 'w').write(text)
        print(fn)


if __name__ == '__main__':
    main()
