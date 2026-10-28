#!/usr/bin/env python3
"""Make MRAs for the TomSVR NSS core from MAME's -listxml of the nss sets.

usage: nss_build.py <listxml.xml> <outdir> <rbf name> --roms=<dir with the MAME zips> [setname ...]
(the zips are read for each game's SNES header: cartridge RAM size)

ioctl index 0 (SNES cart, as the MiSTer SNES loader expects it):
  0x0000  0x200-byte header: byte 0 = (ram size << 4) | rom size (1 KB << n), byte 1 = map type (0 = LoROM)
  0x0200  game PRG ROM (MAME region user3, in order)
ioctl index 5 (NSS board):
  0x00000 BIOS 32 KB (nss.zip, BIOS "single" nss-ic14.02.ic14 unless --bios)
  0x08000 INST ROM, the upper 8 KB of the 32 KB EPROM (EPROM A13/A14 are wired high on the cart)
  0x0a000 security PROM (RP5H01), 16 bytes, then FF fill
  0x0c000 M50458 OSD font (m50458.zip, m50458_char.bin, the one MAME loads last)
ioctl index 9: EEPROM (NVRAM, 128 words)
ioctl index 254: cartridge DIP switches (SNES 4100h)
"""
import os, sys, zipfile, xml.etree.ElementTree as ET

BIOSES = {'single': 'nss-ic14.02.ic14', 'multi': 'nss-c.ic14', 'single3': 'nss-v3.ic14'}
MAMEVERSION = '0264'


def hexbytes(b):
    return ' '.join('%02X' % x for x in b)


def mra(m, bios, rbf, romdir=None):
    name = m.get('name')
    title = m.findtext('description').replace(' (Nintendo Super System)', '')
    roms = m.findall('rom')
    prg = [r for r in roms if r.get('region') == 'user3']
    prg.sort(key=lambda r: int(r.get('offset'), 16))
    inst = [r for r in roms if r.get('region') == 'ibios_rom'][0]
    prom = [r for r in roms if r.get('region') == 'rp5h01' and r.get('status') != 'nodump']
    if not prom:
        return None, None      # no security PROM dump in MAME (nss_smas): the BIOS rejects the cart (NON SLOT)
    prom = prom[0]
    size = sum(int(r.get('size')) for r in prg)
    # SNES header of the game (needs the ROM files: rom/ram size and map from 7fc0)
    rom_n = (size // 1024).bit_length() - 1
    ram_n = 0
    if romdir:
        z = zipfile.ZipFile(os.path.join(romdir, name + '.zip'))
        data = b''.join(z.read(r.get('name')) for r in prg)
        h = data[0x7fc0:0x7fe0]
        assert h[0x15] & 0x0f in (0, 3), (name, hex(h[0x15]))   # LoROM (2.68 / 3.58 MHz)
        ram_n = h[0x18] if h[0x18] <= 7 else 0
    hdr = bytes([(ram_n << 4) | rom_n, 0x00]) + bytes(14)
    zips = f'{name}.zip|nss.zip'
    out = [
        '<!-- TomSVR NSS core (TomSVR_nss). Game PRG ROM, INST ROM and security PROM from MAME '
        f'{name}.zip, BIOS from nss.zip, OSD font from m50458.zip, all unmodified. -->',
        '<misterromdescription>',
        f'    <name>{title} [TomSVR]</name>',
        f'    <setname>{name}</setname>',
        '    <rotation>horizontal</rotation>',
        f'    <mameversion>{MAMEVERSION}</mameversion>',
        f'    <year>{m.findtext("year")}</year>',
        f'    <manufacturer>{m.findtext("manufacturer")}</manufacturer>',
        '    <players>2</players>',
        f'    <rbf>{rbf}</rbf>',
        '    <joystick>8</joystick>',
        '    <switches default="00">',
        *[f'        <dip bits="{i}" name="Cart DIP {i + 1}" ids="Off,On"/>' for i in range(8)],
        '    </switches>',
        f'    <rom index="0" zip="{zips}" md5="None">',
        f'        <part>{hexbytes(hdr)}</part>',
        '        <part repeat="0x1F0">00</part>',
        *[f'        <part name="{r.get("name")}" crc="{r.get("crc")}"/>' for r in prg],
        '    </rom>',
        f'    <rom index="5" zip="{name}.zip|nss.zip|m50458.zip" md5="None">',
        f'        <part name="{BIOSES[bios]}"/>',
        f'        <part name="{inst.get("name")}" crc="{inst.get("crc")}" offset="0x6000" length="0x2000"/>',
        f'        <part name="{prom.get("name")}" crc="{prom.get("crc")}"/>',
        '        <part repeat="0x1FF0">FF</part>',
        '        <part name="m50458_char.bin" crc="011cc342"/>',
        '    </rom>',
        '    <nvram index="9" size="256"/>',
        '    <buttons names="A,B,X,Y,L,R,Select,Start,Coin,Instructions,Page Up,Page Down,Game 1,Game 2,Game 3,Service,Restart"'
        ' default="A,B,X,Y,L,R,R2,Start,Select,L2,-,-,-,-,-,-,-"/>',   # Coin on Select (house rule); SNES Select on R2, Instructions on L2
        '</misterromdescription>', '']
    return title, '\n'.join(out)


def main():
    a = [x for x in sys.argv[1:] if not x.startswith('--')]
    bios = 'single'
    romdir = None
    for x in sys.argv[1:]:
        if x.startswith('--bios='):
            bios = x.split('=', 1)[1]
        if x.startswith('--roms='):
            romdir = x.split('=', 1)[1]
    xmlf, outdir, rbf, only = a[0], a[1], a[2], set(a[3:])
    os.makedirs(outdir, exist_ok=True)
    t = ET.parse(xmlf).getroot()
    n = 0
    for m in t.findall('machine'):
        if m.get('romof') != 'nss' or (only and m.get('name') not in only):
            continue
        title, text = mra(m, bios, rbf, romdir)
        if title is None:
            print('skipped', m.get('name'), '(no security PROM dump)')
            continue
        open(os.path.join(outdir, f'{title.replace(":", " -")} [TomSVR].mra'), 'w').write(text)
        n += 1
    print(n, 'MRAs')


if __name__ == '__main__':
    main()
