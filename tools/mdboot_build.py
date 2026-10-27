#!/usr/bin/env python3
"""Make MRAs for the Mega Drive arcade bootleg core (TomSVR_mdboot) from MAME's sega/megadriv_acbl.cpp.

usage: mdboot_build.py <megadriv_acbl.cpp> <outdir> [setname ...]

ROM image sent to the core (ioctl index 0, see megatech/rtl/mdb_io.sv and MegaDrive.sv MDBOOT):
  0x000000  header, 16 bytes: board family, descramble scheme, Conny protection address bits 23-16 and value,
            flags (bit 0 6-button pads, bit 1 US console); zero fill to 0x001000
  0x001000  PIC16C57 program, 2048 little-endian words (first 0x1000 bytes of the MAME "mcu" region); zero fill
  0x010000  game ROM as MAME's maincpu region (68000 order, gaps filled), before MAME's init_* descrambling:
            the core descrambles while loading, so the zips stay unmodified
DIP switches: MRA <switches> bytes 0-2 = what the board reads as DSWA, DSWB, DSWC (sonic2mb: the high byte of its
DSW port).
"""
import os, re, sys
from xml.sax.saxutils import escape

MAMEVERSION = '0288'  # set list checked against mamedev master on 2026-10-27
# set: (family, scheme, prot_hi, prot_val, flags)   flags bit 0 = 6-button pads, bit 1 = US console (init_megadriv)
BOARDS = {
    'aladmdb':   (6, 0, 0, 0, 0),
    'sonic2mb':  (5, 0, 0, 0, 0),
    'barek2mb':  (6, 0, 0, 0, 0),
    'jparkmb':   (7, 0, 0, 0, 0),
    'barekch':   (1, 3, 0, 0, 1),
    'mk3mdb':    (1, 1, 0, 0, 3),
    'ssf2mdb':   (1, 0, 0, 0, 1),
    'srmdb':     (1, 2, 0, 0, 2),
    'barek3mb':  (4, 5, 0, 0, 0),
    'barek2ch':  (3, 4, 0, 0, 0),
    'biohzdmb':  (2, 6, 0, 0, 0),
    'contrambc': (8, 0, 0x86, 0x40, 0),
    'sidepmbc':  (8, 0, 0x8a, 0x80, 0),
    '3in1mbc':   (9, 0, 0x88, 0x80, 0),
    'barek3mbc': (8, 0, 0x82, 0x40, 0),
    'mickeycmb': (8, 0, 0x8c, 0x80, 0),
}
# which input port the board reads as switch byte 0/1/2 (family -> port names; sonic2mb: high byte of "DSW")
DSWPORTS = {1: ['DSWA', 'DSWB', 'DSWC'], 2: ['DSWA', 'DSWB', 'DSWC'], 3: ['DSWA', 'DSWB'], 4: ['DSW'],
            5: ['DSW'], 6: ['DSW'], 7: [], 8: ['DSW'], 9: ['DSW']}
ROMRE = re.compile(r'(ROM_LOAD16_WORD_SWAP|ROM_LOAD16_BYTE|ROM_LOAD|ROM_CONTINUE)\s*\((.*?)\)\s*(?://.*)?$', re.M)


def ports(s):
    """{inputs name: body} with PORT_INCLUDE resolved (included body first)."""
    raw = {m.group(1): m.group(2) for m in
           re.finditer(r'INPUT_PORTS_START\s*\(\s*(\w+)\s*\)(.*?)INPUT_PORTS_END', s, re.S)}

    def full(n):
        b = raw.get(n, '')
        inc = re.search(r'PORT_INCLUDE\s*\(\s*(\w+)\s*\)', b)
        return (full(inc.group(1)) if inc else '') + b
    return {n: full(n) for n in raw}


def port_section(body, pname):
    """Last definition of port pname (PORT_START or PORT_MODIFY) up to the next port."""
    parts = re.split(r'(PORT_(?:START|MODIFY)\s*\(\s*"\w+"\s*\))', body)
    out = None
    for i in range(1, len(parts), 2):
        if re.search(rf'"{pname}"', parts[i]):
            out = parts[i + 1] if 'START' in parts[i] or out is None else out + parts[i + 1]
    return out


def dips(body, family):
    lines, dflt = [], [0xff, 0xff, 0xff]
    for byte, pname in enumerate(DSWPORTS[family]):
        sec = port_section(body, pname)
        if sec is None:
            continue
        shift = 8 if family == 5 else 0
        for d in re.finditer(r'PORT_DIPNAME\(\s*(0x\w+),\s*(0x\w+),\s*(?:DEF_STR\s*\(\s*(\w+)\s*\)|"([^"]+)")\s*\)'
                             r'(.*?)(?=PORT_DIPNAME|PORT_DIPUNKNOWN|PORT_DIPUNUSED|PORT_BIT|$)', sec, re.S):
            mask, dv = int(d.group(1), 0) >> shift, int(d.group(2), 0) >> shift
            if not mask or mask > 0xff:
                continue
            label = (d.group(3) or d.group(4)).replace('_', ' ')
            bits = [b for b in range(8) if mask >> b & 1]
            vals = {}
            for v in re.finditer(r'^\s*PORT_DIPSETTING\(\s*(0x\w+),\s*(?:DEF_STR\s*\(\s*(\w+)\s*\)|"([^"]+)")\s*\)',
                                 d.group(5), re.M):
                k = (int(v.group(1), 0) >> shift) >> bits[0]
                vals.setdefault(k, (v.group(2) or v.group(3)).replace('_', ' '))
            ids = ','.join(vals.get(i, '-') for i in range(1 << len(bits)))
            lo, hi = bits[0] + 8 * byte, bits[-1] + 8 * byte
            b = f'{lo}' if lo == hi else f'{lo},{hi}'
            lines.append(f'        <dip bits="{b}" name="{label}" ids="{ids}"/>')
            dflt[byte] = (dflt[byte] & ~mask | dv) & 0xff
    return lines, dflt


def parse(src):
    s = open(src).read()
    sets = {}
    for m in re.finditer(r'ROM_START\(\s*(\w+)\s*\)(.*?)ROM_END', s, re.S):
        name, body = m.group(1), m.group(2)
        regions = re.split(r'ROM_REGION\w*\(', body)[1:]
        ops, mcu = [], None
        for r in regions:
            rname = re.match(r'[^,]*,\s*"(\w+)"', r).group(1)
            last = None
            for k, a in ROMRE.findall(r):
                a = [x.strip() for x in a.split(',')]
                if k == 'ROM_CONTINUE':        # the next part of the previous file (mk3mdb)
                    op = dict(last, off=int(a[0], 0), len=int(a[1], 0), foff=last['foff'] + last['len'])
                else:
                    j = ','.join(a)
                    crc = re.search(r'CRC\((\w+)\)', j)
                    op = dict(kind=k, name=a[0].strip('"'), off=int(a[1], 0), len=int(a[2], 0),
                              crc=crc.group(1) if crc else None, foff=0)
                last = op
                if rname == 'maincpu':
                    ops.append(op)
                elif rname == 'mcu' and op['crc']:
                    mcu = op
        sets[name] = dict(ops=ops, mcu=mcu, erase_ff='ROMREGION_ERASEFF' in body.split('"maincpu"')[1][:40])
    game = re.compile(r'GAME\(\s*(\d+),\s*(\w+),\s*(\w+),\s*\w+,\s*(\w+),\s*\w+,\s*[\w<>]+,\s*\w+,\s*"([^"]+)",'
                      r'\s*"([^"]+)",\s*([^)]*)\)')
    for year, n, parent, inp, manufacturer, title, flags in game.findall(s):
        if n in sets:
            sets[n].update(year=year, parent=parent, inputs=inp, manufacturer=manufacturer, title=title,
                           flags=flags.strip())
    return sets, ports(s)


def P(op, full=False):
    """part attributes; a part of a file (ROM_CONTINUE, or a file longer than MAME loads) gets offset/length"""
    t = f'name="{op["name"]}" crc="{op["crc"]}"'
    if not full:
        t += (f' offset="0x{op["foff"]:X}"' if op['foff'] else '') + f' length="0x{op["len"]:X}"'
    return t


def game_lines(name, st):
    """Interleave blocks for the maincpu region, gaps filled; returns (lines, size)."""
    ops = st['ops']
    fill = 'FF' if st['erase_ff'] else '00'
    blocks = []                                    # (offset, length, lines)
    byte_ops = sorted([o for o in ops if o['kind'] == 'ROM_LOAD16_BYTE'], key=lambda o: o['off'])
    while byte_ops:
        ev = byte_ops.pop(0)
        assert ev['off'] % 2 == 0, (name, ev)
        od = [o for o in byte_ops if o['off'] == ev['off'] + 1]
        assert od and od[0]['len'] == ev['len'], (name, ev)
        byte_ops.remove(od[0])
        blocks.append((ev['off'], 2 * ev['len'], ['        <interleave output="16">',
                                                   f'            <part {P(ev)} map="01"/>',
                                                   f'            <part {P(od[0])} map="10"/>',
                                                   '        </interleave>']))
    for o in ops:
        if o['kind'] == 'ROM_LOAD16_WORD_SWAP':
            blocks.append((o['off'], o['len'], ['        <interleave output="16">',
                                                f'            <part {P(o)} map="12"/>', '        </interleave>']))
        elif o['kind'] == 'ROM_LOAD':
            raise SystemExit(f'{name}: unhandled ROM_LOAD in maincpu')
    blocks.sort()
    lines, pos = [], 0
    for off, ln, bl in blocks:
        assert off >= pos, (name, hex(off), hex(pos))
        if off > pos:
            lines.append(f'        <part repeat="0x{off - pos:X}">{fill}</part>')
        lines += bl
        pos = off + ln
    return lines, pos


def mra(name, st, body):
    fam, scheme, phi, pval, flags = BOARDS[name]
    glines, size = game_lines(name, st)
    dl, dflt = dips(body, fam)
    title = escape(st['title'])
    hdr = ' '.join(f'{b:02X}' for b in [fam, scheme, phi, pval, flags] + [0] * 11)
    if st['mcu']:
        pic = [f'        <part {P(dict(st["mcu"], len=0x1000))}/>']
    else:
        pic = ['        <part repeat="0x1000">00</part>']
    six = flags & 1
    # coin = core button 5 (joystick bit 8) on the pad's Select; this tag overrides the core's own J1 names.
    # 6-button sets use the MiSTer Genesis core's name map (C = R, Z = L), which suits 6-button pads such as the 8BitDo M30
    names = 'A,B,C,Start,Coin,X,Y,Z' if six else 'A,B,C,Start,Coin'
    dflt_btn = 'A,B,R,Start,Select,X,Y,L' if six else 'A,B,X,Start,Select'
    zips = f'{name}.zip' if st['parent'] == '0' else f'{name}.zip|{st["parent"]}.zip'
    out = [
        f'<!-- {title} on TomSVR_mdboot, a personal MiSTer core for the Mega Drive based arcade bootleg boards',
        f'     (MAME sega/megadriv_acbl.cpp "{name}"), built on MegaDrive_MiSTer (Nuked-MD by nukeykt, MiSTer port by',
        '     Alexey Melnikov / Sorgelig). The ROM is assembled from your own MAME zips, unmodified.',
        '     Requires TomSVR_mdboot.rbf. -->',
        '<misterromdescription>',
        f'    <name>{title} [TomSVR]</name>',
        f'    <setname>{name}</setname>',
        '    <rotation>horizontal</rotation>',
        f'    <mameversion>{MAMEVERSION}</mameversion>',
        f'    <year>{st["year"]}</year>',
        f'    <manufacturer>{escape(st["manufacturer"])}</manufacturer>',
        '    <players>2</players>',
        '    <rbf>TomSVR_mdboot</rbf>',
        '    <joystick>8</joystick>',
    ]
    if dl:
        out += [f'    <switches default="{dflt[0]:02X},{dflt[1]:02X},{dflt[2]:02X}">', *dl, '    </switches>']
    out += [
        f'    <rom index="0" zip="{zips}" md5="None">',
        f'        <part>{hdr}</part>',
        '        <part repeat="0xFF0">00</part>',
        *pic,
        '        <part repeat="0xE000">00</part>',
        *glines,
        '    </rom>',
        f'    <buttons names="{names}" default="{dflt_btn}"/>',
        '</misterromdescription>', '']
    return '\n'.join(out), size


def main():
    src, outdir, only = sys.argv[1], sys.argv[2], set(sys.argv[3:])
    os.makedirs(outdir, exist_ok=True)
    sets, pb = parse(src)
    n = 0
    for name in BOARDS:
        st = sets[name]
        if only and name not in only:
            continue
        assert st['flags'] == '0', (name, st['flags'])
        text, size = mra(name, st, pb[st['inputs']])
        t = st['title'].replace(':', ' -').replace('/', '-').replace(' - The New', ': The New').replace(':', ' -')
        fn = os.path.join(outdir, f'{t} [TomSVR].mra')
        open(fn, 'w').write(text)
        n += 1
        print(f'{name:10s} game 0x{size:06x}  {st["title"]}')
    print(n, 'MRAs')


if __name__ == '__main__':
    main()
