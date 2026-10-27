#!/usr/bin/env python3
"""Make MRAs for the Sega Mega Play core (TomSVR_megaplay) from MAME's sega/megaplay.cpp.

usage: megaplay_build.py <megaplay.cpp> <outdir> [setname ...]

ROM image sent to the core (ioctl index 0):
  0x000000  BIOS ROM, 128 kB (megaplay.zip, BIOS "ver1" ep15294.ic2; MAME says "ver2" does not boot)
  0x020000  instruction ROM epr-15175-NN, 32 kB (MAME copies it to both bytes of 0x300000-0x30ffff in the
            68000 space, where the BIOS reads it through its window; the core maps it there itself)
  0x028000  header, 16 bytes: byte 1 = cart number NN; zero fill to 0x030000
  0x030000  game ROM as the 68000 sees it, big-endian (byte 0 = high byte of word 0), like a .bin file

MRA interleave maps as in megatech_build.py: "01" even (high byte) file, "10" odd file, "12" undoes
ROM_LOAD16_WORD_SWAP.
"""
import os, re, sys

BIOSES = {'ver1': ('ep15294.ic2', 'aa8dc2d8'), 'ver2': ('epr-a15294.ic2', 'f97c68aa')}
MAMEVERSION = '0288'  # set list checked against mamedev master on 2026-10-26
# MAME megaplay DSW0 (coin slots 1/2, bits 0-7) and DSW1 (per-game SW3, bits 8-11); defaults FF and the game's
# values 0..15 (MiSTer DIP ids must be short: the combined settings are abbreviated)
COINS = 'Free Play,1C/1C 2C/3C,1C/1C 4C/5C,1C/1C 5C/6C,2C/1C 4C/3C,2C/1C 5C/3C 6C/4C,2C/3C,4C/1C,3C/1C,2C/1C,' \
        '1C/6C,1C/5C,1C/4C,1C/3C,1C/2C,1C/1C'
COINS2 = COINS.replace('Free Play', '1C/1C', 1)  # slot 2 has no free play setting (MAME " 1 coin/1 credit")
ROMRE = re.compile(r'(ROM_LOAD16_WORD_SWAP|ROM_LOAD16_BYTE|ROM_LOAD)\s*\((.*?)\)\s*(?://.*)?$', re.M)


def dips(src):
    """Per-game SW3 settings from the INPUT_PORTS blocks: {inputs name: (default, [dip lines])}."""
    s = open(src).read()
    out = {}
    for m in re.finditer(r'INPUT_PORTS_START\s*\(\s*(\w+)\s*\)(.*?)INPUT_PORTS_END', s, re.S):
        name, body = m.group(1), m.group(2)
        if 'PORT_MODIFY("DSW1")' not in body:
            continue
        body = body.split('PORT_MODIFY("DSW1")')[1]
        lines, dflt = [], 0
        for d in re.finditer(r'PORT_DIPNAME\(\s*(0x\w+),\s*(0x\w+),\s*(?:DEF_STR\s*\(\s*(\w+)\s*\)|"([^"]+)")\s*\)'
                             r'(.*?)(?=PORT_DIPNAME|$)', body, re.S):
            mask, dv = int(d.group(1), 0), int(d.group(2), 0)
            label = (d.group(3) or d.group(4)).replace('_', ' ')
            bits = [b for b in range(8) if mask >> b & 1]
            vals = {}
            for v in re.finditer(r'PORT_DIPSETTING\(\s*(0x\w+),\s*(?:DEF_STR\s*\(\s*(\w+)\s*\)|"([^"]+)")\s*\)',
                                 d.group(5)):
                vals[int(v.group(1), 0) >> bits[0]] = (v.group(2) or v.group(3)).replace('_', ' ')
            ids = ','.join(vals.get(i, '-') for i in range(1 << len(bits)))
            b = f'{bits[0] + 8}' if len(bits) == 1 else f'{bits[0] + 8},{bits[-1] + 8}'
            lines.append(f'        <dip bits="{b}" name="{label}" ids="{ids}"/>')
            dflt |= dv
        out[name] = (dflt, lines)
    return out


def parse(src):
    s = open(src).read()
    sets = {}
    for m in re.finditer(r'ROM_START\(\s*(\w+)\s*\)(.*?)ROM_END', s, re.S):
        name, body = m.group(1), m.group(2)
        if name == 'megaplay':
            continue
        main = body.split('"maincpu"')[1].split('ROM_REGION(')[0]
        user = body.split('"user1"')[1].split('ROM_REGION(')[0]
        ops = []
        for part in (main, user):
            for k, a in ROMRE.findall(part):
                a = [x.strip() for x in a.split(',')]
                crc = re.search(r'CRC\((\w+)\)', ','.join(a)).group(1)
                ops.append(dict(kind=k, name=a[0].strip('"'), off=int(a[1], 0), len=int(a[2], 0), crc=crc,
                                instr=part is user, bad='BAD_DUMP' in ','.join(a)))
        sets[name] = dict(ops=ops)
    game = re.compile(r'GAME\(\s*([^,]+),\s*(\w+),\s*(\w+),\s*\w+,\s*(\w+),\s*\w+,\s*\w+,\s*\w+,\s*"([^"]+)",'
                      r'\s*"([^"]+)",\s*([^)]*)\)')
    for year, n, parent, inp, manufacturer, title, flags in game.findall(s):
        if n in sets:
            sets[n].update(year=year.strip(), parent=parent, inputs=inp, manufacturer=manufacturer, title=title,
                           flags=flags.strip())
    missing = [n for n, st in sets.items() if 'title' not in st]
    assert not missing, missing
    return sets


def P(op):
    return f'name="{op["name"]}" crc="{op["crc"]}"'


def game_lines(name, ops):
    kinds = [o['kind'] for o in ops]
    if kinds == ['ROM_LOAD16_WORD_SWAP']:
        return ['        <interleave output="16">', f'            <part {P(ops[0])} map="12"/>',
                '        </interleave>'], ops[0]['len']
    if kinds == ['ROM_LOAD16_BYTE', 'ROM_LOAD16_BYTE']:
        ev = [o for o in ops if o['off'] % 2 == 0][0]
        od = [o for o in ops if o['off'] % 2 == 1][0]
        assert ev['off'] == 0 and od['off'] == 1 and ev['len'] == od['len'], name
        return ['        <interleave output="16">', f'            <part {P(ev)} map="01"/>',
                f'            <part {P(od)} map="10"/>', '        </interleave>'], 2 * ev['len']
    raise SystemExit(f'{name}: unhandled ROM layout {kinds}')


def mra(name, st, bios, dipinfo):
    instr = [o for o in st['ops'] if o['instr']]
    assert len(instr) == 1 and instr[0]['len'] == 0x8000, name
    instr = instr[0]
    glines, size = game_lines(name, [o for o in st['ops'] if not o['instr']])
    nn = int(re.search(r'15175-(\d+)', instr['name']).group(1)) if '15175-' in instr['name'] else 0
    bname, bcrc = BIOSES[bios]
    dflt, dl = dipinfo.get(st['inputs'], (0x0f, []))
    title = st['title']
    hdr = f'00 {nn:02X} 00 00 00 00 00 00 00 00 00 00 00 00 00 00'
    notes = []
    if 'MACHINE_NOT_WORKING' in st['flags']:
        notes.append('MAME marks this set as not working. ')
    zips = '|'.join(dict.fromkeys([f'{name}.zip', f'{st["parent"]}.zip', 'megaplay.zip']))
    coin = [f'        <dip bits="0,3" name="Coin Slot 1" ids="{COINS}"/>',
            f'        <dip bits="4,7" name="Coin Slot 2" ids="{COINS2}"/>']
    out = [
        f'<!-- {title} on TomSVR_megaplay, a personal MiSTer core for the Sega Mega Play (MAME megaplay.cpp "{name}"),',
        '     built on MegaDrive_MiSTer (Nuked-MD by nukeykt, MiSTer port by Alexey Melnikov / Sorgelig).',
        f'     {"".join(notes)}The ROM is assembled from your own MAME zips, unmodified. Requires TomSVR_megaplay.rbf. -->',
        '<misterromdescription>',
        f'    <name>{title} [TomSVR]</name>',
        f'    <setname same_dir="1">{name}</setname>',
        '    <rotation>horizontal</rotation>',
        f'    <mameversion>{MAMEVERSION}</mameversion>',
        f'    <year>{st["year"]}</year>',
        f'    <manufacturer>{st["manufacturer"]}</manufacturer>',
        '    <players>2</players>',
        '    <rbf>TomSVR_megaplay</rbf>',
        '    <joystick>8</joystick>',
        f'    <switches default="FF,{dflt | 0xf0:02X}">',
        *coin, *dl,
        '    </switches>',
        f'    <rom index="0" zip="{zips}" md5="None">',
        f'        <part name="{bname}" crc="{bcrc}"/>',
        f'        <part {P(instr)}/>',
        f'        <part>{hdr}</part>',
        '        <part repeat="0x7FF0">00</part>',
        *glines,
        '    </rom>',
        '    <buttons names="A,B,C,Start,Mode,X,Y,Z,Coin,Select,Service,Test" default="A,B,X,Start,-,-,-,-,Select,R,L,-"/>',
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
    sets, dipinfo = parse(src), dips(src)
    n = 0
    for name, st in sets.items():
        if only and name not in only:
            continue
        text, size = mra(name, st, bios, dipinfo)
        fn = os.path.join(outdir, f'{st["title"].replace(":", " -").replace("/", "-")} [TomSVR].mra')
        open(fn, 'w').write(text)
        n += 1
        print(f'{name:10s} game 0x{size:06x}  {st["title"]}')
    print(n, 'MRAs')


if __name__ == '__main__':
    main()
