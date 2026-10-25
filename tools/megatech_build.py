#!/usr/bin/env python3
"""Make MRAs for the Sega Mega-Tech core from MAME's sega/megatech.cpp.

usage: megatech_build.py <megatech.cpp> <outdir> [setname ...]

ROM image sent to the core (ioctl index 0), see docs/design.md:
  0x000000  BIOS ROM, 32 kB (megatech.zip, BIOS "ver1" epr-12664.20 unless --bios)
  0x008000  instruction ROM epr-12368-NN, 32 kB (MAME loads it on the odd bytes of 0x300000;
            the core maps it there itself)
  0x010000  header, 16 bytes: byte 0 bit 0 = SMS cart (MAME sms_pin FF); byte 1 = cart number NN
  0x010010  zero fill to 0x020000
  0x020000  game ROM as the 68000 sees it, big-endian (byte 0 = high byte of word 0), like a .bin file

MRA interleave maps: the rightmost digit is output byte 0, the digit says which input byte goes there.
So a big-endian stream needs "01" for the even (high byte) file of a pair, "10" for the odd one, and "12"
to undo ROM_LOAD16_WORD_SWAP.
"""
import os, re, sys

BIOSES = {  # MAME ROM_SYSTEM_BIOS order
    'ver1':   ('epr-12664.20',  'f71e9526'),
    'ver0a':  ('epr-12263a.20', '07c3f423'),
    'ver0b':  ('epr-12263b.20', 'ca26c87a'),
    'ver0aa': ('epr-12604a.20', '884e4aa5'),
}
MAMEVERSION = '0288'  # set list checked against mamedev master on 2026-10-23
DIP_DEFAULT = '7F,A1'  # MAME BIOS_DSW0 / BIOS_DSW1 defaults
# MAME megatech INPUT_PORTS (BIOS_DSW0 = bits 0-7, BIOS_DSW1 = bits 8-15), values listed from 0 up
DIPS = [
    '        <dip bits="0" name="Coin Slot 4" ids="Inhibit,Accept"/>',
    '        <dip bits="1" name="Coin Slot 3" ids="Inhibit,Accept"/>',
    '        <dip bits="2,4" name="Coin Slot 3/4 Value" ids="1C/10C,1C/8C,1C/6C,1C/5C,1C/4C,1C/3C,1C/2C,1C/1C"/>',
    '        <dip bits="5,7" name="Coin Slot 2 Value" ids="Inhibit,2C/1C,1C/1C,1C/2C,1C/3C,1C/4C,1C/5C,1C/6C"/>',
    '        <dip bits="8,11" name="Coin Slot 1 Value" ids="Inhibit,1C/1C,1C/2C,1C/3C,1C/4C,1C/5C,1C/6C,1C/7C,'
    '1C/8C,1C/9C,1C/10C,1C/11C,1C/12C,1C/13C,1C/14C,1C/15C"/>',
    '        <dip bits="12,15" name="Time Per Credit" ids="Free Play,7:30,7:00,6:30,6:00,5:30,5:00,4:30,4:00,'
    '3:30,3:00,2:30,2:00,1:30,1:00,0:30"/>',
]

ROMRE = re.compile(r'(ROM_LOAD16_WORD_SWAP|ROM_LOAD16_BYTE|ROM_LOAD|ROM_CONTINUE)\s*\((.*)\)\s*$', re.M)


def parse(src):
    s = open(src).read()
    sets = {}
    for m in re.finditer(r'ROM_START\(\s*(\w+)\s*\)(.*?)ROM_END', s, re.S):
        name, body = m.group(1), m.group(2)
        if name == 'megatech':
            continue
        cart = body.split('"mt_slot1:cart"')[1].split('ROM_REGION(')[0]
        ops = []
        for k, a in ROMRE.findall(cart):
            a = [x.strip() for x in a.split(',')]
            if k == 'ROM_CONTINUE':
                ops.append(dict(kind=k, off=int(a[0], 0), len=int(a[1], 0)))
            else:
                crc = re.search(r'CRC\((\w+)\)', ','.join(a)).group(1)
                ops.append(dict(kind=k, name=a[0].strip('"'), off=int(a[1], 0), len=int(a[2], 0), crc=crc,
                                bad='BAD_DUMP' in ','.join(a)))
        sms = 'ERASEFF' in body.split('"sms_pin"')[1].split(')')[0]
        sets[name] = dict(ops=ops, sms=sms)
    game = re.compile(r'GAME\(\s*([^,]+),\s*(\w+),\s*(\w+),\s*\w+,\s*\w+,\s*\w+,\s*\w+,\s*\w+,\s*"([^"]+)",\s*"([^"]+)"')
    for year, n, parent, manufacturer, title in game.findall(s):
        sets[n].update(year=year.strip(), parent=parent, manufacturer=manufacturer, title=title)
    missing = [n for n, st in sets.items() if 'title' not in st]
    assert not missing, missing
    return sets


def P(op, extra=''):
    return f'name="{op["name"]}" crc="{op["crc"]}"{extra}'


def cart_parts(name, ops, sms):
    """Return (instruction-ROM op, list of MRA lines for the game ROM, game size)."""
    instr = [o for o in ops if o.get('off') == 0x300001]
    assert len(instr) == 1, name
    instr = instr[0]
    game = [o for o in ops if o is not instr]
    lines, size = [], 0
    kinds = [o['kind'] for o in game]
    if sms:
        # SMS carts: MAME copies the region's bytes straight into Z80 space, and LOAD16_WORD_SWAP into a
        # 16-bit BE region leaves them in file order, so the file goes in as it is (like an .sms file).
        assert kinds == ['ROM_LOAD16_WORD_SWAP'] and game[0]['off'] == 0, name
        lines = [f'        <part {P(game[0])}/>']
        size = game[0]['len']
    elif kinds == ['ROM_LOAD16_WORD_SWAP']:
        o = game[0]
        lines = ['        <interleave output="16">', f'            <part {P(o)} map="12"/>', '        </interleave>']
        size = o['len']
    elif kinds == ['ROM_LOAD']:  # mt_fwrld, mt_srbb: already in console byte order
        lines = [f'        <part {P(game[0])}/>']
        size = game[0]['len']
    elif kinds == ['ROM_LOAD16_BYTE', 'ROM_LOAD16_BYTE']:  # mt_tetri, mt_calga
        ev = [o for o in game if o['off'] % 2 == 0][0]
        od = [o for o in game if o['off'] % 2 == 1][0]
        assert ev['off'] == 0 and od['off'] == 1 and ev['len'] == od['len'], name
        lines = ['        <interleave output="16">', f'            <part {P(ev)} map="01"/>',
                 f'            <part {P(od)} map="10"/>', '        </interleave>']
        size = 2 * ev['len']
    elif kinds == ['ROM_LOAD16_WORD_SWAP', 'ROM_LOAD16_WORD_SWAP', 'ROM_CONTINUE']:  # mt_gng
        a, b, c = game
        assert (a['off'], a['len'], b['off'], b['len'], c['off'], c['len']) == \
            (0, 0x20000, 0x80000, 0x20000, 0x20000, 0x60000), name
        # 0x00000 = a, 0x20000 = b[0x20000:0x80000], 0x80000 = b[0:0x20000]
        hi = ' offset="0x20000" length="0x60000"'
        lo = ' offset="0x0" length="0x20000"'
        lines = ['        <interleave output="16">', f'            <part {P(a)} map="12"/>', '        </interleave>',
                 '        <interleave output="16">', f'            <part {P(b, hi)} map="12"/>', '        </interleave>',
                 '        <interleave output="16">', f'            <part {P(b, lo)} map="12"/>', '        </interleave>']
        size = 0xa0000
    else:
        raise SystemExit(f'{name}: unhandled ROM layout {kinds}')
    return instr, lines, size


def mra(name, st, bios):
    instr, glines, size = cart_parts(name, st["ops"], st["sms"])
    nn = int(re.search(r'12368-(\d+)', instr['name']).group(1))
    bname, bcrc = BIOSES[bios]
    title = st['title']
    hdr = f'{1 if st["sms"] else 0:02X} {nn:02X} 00 00 00 00 00 00 00 00 00 00 00 00 00 00'
    bad = any(o.get('bad') for o in st['ops'])
    zips = f'{name}.zip|{st["parent"] if st["parent"] != "megatech" else "megatech"}.zip|megatech.zip'
    zips = '|'.join(dict.fromkeys(zips.split('|')))
    out = [
        f'<!-- {title} on TomSVR_megatech, a personal MiSTer core for the Sega Mega-Tech (MAME megatech.cpp "{name}"),',
        '     built on MegaDrive_MiSTer (Nuked-MD by nukeykt, MiSTer port by Alexey Melnikov / Sorgelig).',
        f'     {"SMS cart (runs in the VDP Master System mode). " if st["sms"] else ""}'
        f'{"MAME marks this cart dump BAD_DUMP. " if bad else ""}'
        'The ROM is assembled from your own MAME zips, unmodified. Requires TomSVR_megatech.rbf. -->',
        '<misterromdescription>',
        f'    <name>{title} [TomSVR]</name>',
        f'    <setname>{name}</setname>',
        '    <rotation>horizontal</rotation>',
        f'    <mameversion>{MAMEVERSION}</mameversion>',
        f'    <year>{st["year"]}</year>',
        f'    <manufacturer>{st["manufacturer"]}</manufacturer>',
        '    <players>2</players>',
        '    <rbf>TomSVR_megatech</rbf>',
        '    <joystick>8</joystick>',
        f'    <switches default="{DIP_DEFAULT}">',
        *DIPS,
        '    </switches>',
        f'    <rom index="0" zip="{zips}" md5="None">',
        f'        <part name="{bname}" crc="{bcrc}"/>',
        f'        <part {P(instr)}/>',
        f'        <part>{hdr}</part>',
        '        <part repeat="0xFFF0">00</part>',
        *glines,
        '    </rom>',
        '    <nvram index="9" size="8192"/>',  # BIOS RAM 4000-5fff (operator settings, bookkeeping)
        '    <buttons names="A,B,C,Start,Mode,X,Y,Z,Coin,Select,Enter,Test" default="A,B,X,Start,-,-,-,-,Select,R,L,-"/>',
        '</misterromdescription>', '']
    return '\n'.join(out), size


def main():
    a = [x for x in sys.argv[1:] if not x.startswith('--')]
    bios = 'ver1'
    for x in sys.argv[1:]:
        if x.startswith('--bios='):
            bios = x.split('=', 1)[1]
    src, outdir, only = a[0], a[1], set(a[2:])
    os.makedirs(outdir, exist_ok=True)
    sets = parse(src)
    n = 0
    for name, st in sets.items():
        if only and name not in only:
            continue
        text, size = mra(name, st, bios)
        fn = os.path.join(outdir, f'{st["title"].replace(":", " -")} [TomSVR].mra')
        open(fn, 'w').write(text)
        n += 1
        print(f'{name:9s} {"SMS" if st["sms"] else "MD "} game 0x{size:06x}  {st["title"]}')
    print(n, 'MRAs')


if __name__ == '__main__':
    main()
