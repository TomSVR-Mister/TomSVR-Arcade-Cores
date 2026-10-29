#!/usr/bin/env python3
"""Make MRAs for the TomSVR NSS core from MAME's -listxml of the nss sets.

usage: nss_build.py <listxml.xml> <outdir> <rbf name> --roms=<dir with the MAME zips> [setname ...]
(the zips are read for each game's SNES header: cartridge RAM size)

Makes one MRA per game (the game in slot 1) and two 3-slot MRAs: the launch trio F-Zero / Super Mario World / Super Tennis, and one with every game loaded,
whose slots are chosen in the core's OSD.

Each game has a fixed game number, the order of the core's OSD slot menu (GAMES below). An MRA loads its games in
"positions" 0..n-1:
ioctl index 0: the SNES PRG ROM of position p at p * 1 MB (MAME region user3, in order), FF fill to 1 MB
ioctl index 5 (NSS board):
  0x00000 BIOS 32 KB (nss.zip)
  0x08000 M50458 OSD font (m50458.zip, m50458_char.bin, the one MAME loads last), 00 fill
  0x0a000 game table, 16 bytes per position (12): present, game number, SNES ROM size n (1 KB << n), RAM size n
  0x0a0f0 default game number of slots 1-3 (ff = empty)
  0x0a100 security PROMs (RP5H01), 16 bytes per position
  0x0c000 INST ROMs, the upper 8 KB of each 32 KB EPROM (EPROM A13/A14 are wired high on the cart), 8 KB per position
ioctl index 9: EEPROM (NVRAM, 128 words)
ioctl index 254: cartridge DIP switches (SNES 4100h), one byte per slot
"""
import os, sys, zipfile, xml.etree.ElementTree as ET

# MAME calls nss-c "multi" and nss-ic14.02 "single", but every NSS BIOS drives 3 slots. nss-c is a version 1 BIOS:
# it doesn't support skill-mode carts (ActRaiser, Addams Family, Lethal Weapon, Robocop 3 show NON SLOT, in MAME too),
# so all MRAs use version 2, nss-ic14.02 (DogP: v2 supports skill mode).
BIOSES = {'v2': 'nss-ic14.02.ic14', 'v1': 'nss-c.ic14', 'v3': 'nss-v3.ic14'}
BIOS_CRC = {'nss-ic14.02.ic14': 'e06cb58f', 'nss-c.ic14': 'a8e202b3', 'nss-v3.ic14': 'ac385b53'}
MAMEVERSION = '0264'
GAMES = ['nss_actr', 'nss_adam', 'nss_aten', 'nss_con3', 'nss_fzer', 'nss_lwep', 'nss_ncaa', 'nss_rob3',
         'nss_skin', 'nss_smw', 'nss_ssoc', 'nss_sten']          # = OSD slot menu order (SNES.sv CONF_STR)
TRIO = ['nss_fzer', 'nss_smw', 'nss_sten']
BUTTONS = ('    <buttons names="A,B,X,Y,L,R,Select,Start,Coin,Instructions,Page Up,Page Down,Game 1,Game 2,Game 3,'
           'Service,Restart" default="A,B,X,Y,L,R,R2,Start,Select,L2,-,-,-,-,-,-,-"/>')  # Coin on Select (house rule)


def hexbytes(b):
    return ' '.join('%02X' % x for x in b)


def hexlines(b, ind='        '):
    return [f'{ind}<part>{hexbytes(b[i:i + 16])}</part>' for i in range(0, len(b), 16)]


class Game:
    def __init__(self, m, romdir):
        self.name = m.get('name')
        self.title = m.findtext('description').replace(' (Nintendo Super System)', '')
        self.year, self.manufacturer = m.findtext('year'), m.findtext('manufacturer')
        roms = m.findall('rom')
        self.prg = sorted([r for r in roms if r.get('region') == 'user3'], key=lambda r: int(r.get('offset'), 16))
        self.inst = [r for r in roms if r.get('region') == 'ibios_rom'][0]
        p = [r for r in roms if r.get('region') == 'rp5h01' and r.get('status') != 'nodump']
        self.prom = p[0] if p else None   # nss_smas: no PROM dump, the BIOS rejects the cart (NON SLOT)
        self.size = sum(int(r.get('size')) for r in self.prg)
        assert self.size <= 0x100000 or self.prom is None, self.name
        self.rom_n = (self.size // 1024).bit_length() - 1
        self.ram_n = 0
        if romdir and self.prom is not None:
            z = zipfile.ZipFile(os.path.join(romdir, self.name + '.zip'))
            data = b''.join(z.read(r.get('name')) for r in self.prg)
            h = data[0x7fc0:0x7fe0]
            assert h[0x15] & 0x0f in (0, 3), (self.name, hex(h[0x15]))   # LoROM (2.68 / 3.58 MHz)
            self.ram_n = h[0x18] if h[0x18] <= 7 else 0
        self.num = GAMES.index(self.name) if self.name in GAMES else None


def mra(games, defaults, bios, rbf, title, setname, comment, year, manufacturer, nslots=1):
    zipof = lambda g: f'{g.name}.zip'
    # index 0
    rom0 = []
    for g in games:
        rom0 += [f'        <part zip="{zipof(g)}" name="{r.get("name")}" crc="{r.get("crc")}"/>' for r in g.prg]
        if g.size < 0x100000 and g is not games[-1]:
            rom0.append(f'        <part repeat="0x{0x100000 - g.size:X}">FF</part>')
    # index 5
    table = bytearray(0x100)
    for p, g in enumerate(games):
        table[p * 16:p * 16 + 4] = bytes([1, g.num, g.rom_n, g.ram_n])
    table[0xf0:0xf3] = bytes(defaults + [0xff] * (3 - len(defaults)))
    proms = []
    for g in games:
        proms.append(f'        <part zip="{zipof(g)}" name="{g.prom.get("name")}" crc="{g.prom.get("crc")}"/>')
    pad = 0xc0 - 16 * len(games)
    b = BIOSES[bios]
    rom5 = [f'        <part zip="nss.zip" name="{b}" crc="{BIOS_CRC[b]}"/>',
            '        <part zip="m50458.zip" name="m50458_char.bin" crc="011cc342"/>',
            '        <part repeat="0xE00">00</part>',
            *hexlines(bytes(table)),
            *proms,
            *([f'        <part repeat="0x{pad:X}">00</part>'] if pad else []),
            '        <part repeat="0x1E40">00</part>',
            *[f'        <part zip="{zipof(g)}" name="{g.inst.get("name")}" crc="{g.inst.get("crc")}" offset="0x6000" '
              'length="0x2000"/>' for g in games]]
    dips = []
    for s in range(nslots):
        for i in range(8):
            nm = f'Slot {s + 1} DIP {i + 1}' if nslots > 1 else f'Cart DIP {i + 1}'
            dips.append(f'        <dip bits="{s * 8 + i}" name="{nm}" ids="Off,On"/>')
    zips = '|'.join([zipof(g) for g in games] + ['nss.zip', 'm50458.zip'])
    out = [
        f'<!-- {comment} -->',
        '<misterromdescription>',
        f'    <name>{title} [TomSVR]</name>',
        f'    <setname>{setname}</setname>',
        '    <rotation>horizontal</rotation>',
        f'    <mameversion>{MAMEVERSION}</mameversion>',
        f'    <year>{year}</year>',
        f'    <manufacturer>{manufacturer}</manufacturer>',
        '    <players>2</players>',
        f'    <rbf>{rbf}</rbf>',
        '    <joystick>8</joystick>',
        f'    <switches default="{",".join(["00"] * nslots)}">',
        *dips,
        '    </switches>',
        f'    <rom index="0" zip="{zips}" md5="None">',
        *rom0,
        '    </rom>',
        f'    <rom index="5" zip="{zips}" md5="None">',
        *rom5,
        '    </rom>',
        '    <nvram index="9" size="256"/>',
        BUTTONS,
        '</misterromdescription>', '']
    return '\n'.join(out)


def main():
    a = [x for x in sys.argv[1:] if not x.startswith('--')]
    romdir = None
    for x in sys.argv[1:]:
        if x.startswith('--roms='):
            romdir = x.split('=', 1)[1]
    xmlf, outdir, rbf, only = a[0], a[1], a[2], set(a[3:])
    os.makedirs(outdir, exist_ok=True)
    t = ET.parse(xmlf).getroot()
    games = {}
    for m in t.findall('machine'):
        if m.get('romof') == 'nss':
            games[m.get('name')] = Game(m, romdir)
    n = 0
    for name, g in games.items():
        if only and name not in only:
            continue
        if g.prom is None:
            print('skipped', name, '(no security PROM dump)')
            continue
        text = mra([g], [g.num], 'v2', rbf, g.title, name,
                   f'TomSVR NSS core ({rbf}). Game PRG ROM, INST ROM and security PROM from MAME {name}.zip, BIOS '
                   'from nss.zip, OSD font from m50458.zip, all unmodified.', g.year, g.manufacturer)
        open(os.path.join(outdir, f'{g.title.replace(":", " -")} [TomSVR].mra'), 'w').write(text)
        n += 1
    if not only:
        trio = [games[x] for x in TRIO]
        text = mra(trio, [g.num for g in trio], 'v2', rbf, 'Nintendo Super System (F-Zero, Super Mario World, '
                   'Super Tennis)', 'nss', f'TomSVR NSS core ({rbf}), three cartridges in the 3 slots. ROMs from MAME '
                   'nss.zip, m50458.zip and the game zips, unmodified.', '1991', 'Nintendo', nslots=3)
        open(os.path.join(outdir, 'Nintendo Super System (3 games) [TomSVR].mra'), 'w').write(text)
        allg = [games[x] for x in GAMES]
        text = mra(allg, [games[x].num for x in TRIO], 'v2', rbf, 'Nintendo Super System (all games)', 'nss',
                   f'TomSVR NSS core ({rbf}), all 12 dumped cartridges loaded; '
                   'choose the game in each of the 3 slots in the OSD (Cartridge slots, then Reset). ROMs from MAME '
                   'nss.zip, m50458.zip and the game zips, unmodified.', '1991', 'Nintendo', nslots=3)
        open(os.path.join(outdir, 'Nintendo Super System (all games) [TomSVR].mra'), 'w').write(text)
        n += 2
    print(n, 'MRAs')


if __name__ == '__main__':
    main()
