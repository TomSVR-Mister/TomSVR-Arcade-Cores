#!/usr/bin/env python3
"""Comad boards with work RAM at 0xc00000 and LZ-compressed pictures (Miss World '96, Super Miss World).
   - pictures: decompressor replaced by asm/mw_decomp.s (bg bitmap used as LZ window, no 32 KB RAM needed)
   - work RAM pages -> hidden fg rows (0x51c000-0x51ffff, only touched by the boot clear, which we shorten)
   - sprite shadow / flags -> objaux (0x702000-)"""
import sys, struct, subprocess
sys.path.insert(0, '/tmp/claude-0/-home-claude/e1042311-2b93-5281-bddb-91ed22183aec/scratchpad/work')
from port import *

SHADOW_C0, FLAGS_C0, MARK_C0 = 0x702000, 0x703000, 0x703200
PAD0 = 0x39e10                                   # zero padding after the original decompressor

def ram_map_c0(v):
    for lo, hi, dst in ((0xc00f00, 0xc02f00, 0x51c000), (0xc00000, 0xc00900, 0x51e000), (0xc05000, 0xc05900, 0x51e900),
                        (0xc05f00, 0xc06000, 0x51f200), (0xc07000, 0xc07100, 0x51f300), (0xc07700, 0xc07800, 0x51f700)):
        if lo <= v < hi: return dst + v - lo
spr_map_c0 = lambda v: SHADOW_C0 + (v - 0x700000) if 0x700000 <= v < 0x701000 else None

def asm(name, src, syms):
    o = f'{S}/work/asm/{name}.o'; b = f'{S}/work/asm/{name}.bin'
    args = ['m68k-linux-gnu-as', '-m68000']
    for k, v in syms.items(): args += ['--defsym', '%s=%d' % (k, v)]
    subprocess.run(args + ['-o', o, f'{S}/work/asm/{src}'], check=True)
    subprocess.run(['m68k-linux-gnu-objcopy', '-O', 'binary', '-j', '.text', o, b], check=True)
    nm = subprocess.run(['m68k-linux-gnu-nm', o], capture_output=True, text=True).stdout
    sym = {l.split()[2]: int(l.split()[0], 16) for l in nm.splitlines() if len(l.split()) == 3}
    return open(b, 'rb').read(), sym

def flip_patch(p, base, sym, hi=0x3e000):
    pat = bytes.fromhex('13c000900000'); u = bytes(p.unpatched[:hi])
    hits = [i for i in range(0, hi, 2) if u.startswith(pat, i)]
    for h in hits: p.put(h, bytes.fromhex('4eb9') + L(base + sym['flipw']), 'flip')
    p.log.append('flip bit inverted at %d sound-bank writes' % len(hits))
    assert 1 <= len(hits) <= 6, hits

def one(p, pat, why):
    h = p.find(bytes.fromhex(pat)); assert len(h) == 1, (why, [hex(x) for x in h]); return h[0]

DIPS_MW96 = DIPS_MW

def build(name, setname, title, prog, data, spr, oki, refs, zips, skip=(), timers=(0x80000c, 0x80000e), year='1996',
          manufacturer='Comad', dips=DIPS_MW96, yoff=15, vertical=False):
    p = Port(name, [(0, 'il', prog)] + [(0x100000 * (i + 1), 'il', d) for i, d in enumerate(data)], 0x400000)
    p.identity_layout()
    # --- locate things before relocation (original addresses)
    dec = one(p, '48e7fffe08b9000000c0706443f90052000045f900c08000', 'decompressor')
    sv = [h - 6 for h in p.find(bytes.fromhex('41f90058000043f900c03000'))]
    assert len(sv) == 2, sv
    boot = one(p, '227c00c00000203c00003fff4299', 'boot clear')
    fgc = one(p, '227c00500001203c00003fff', 'fg clear')
    # refs inside code we replace / disable are skipped
    dead = set(range(dec, dec + 0x2b4)) | set(range(sv[0], sv[0] + 0x40)) | set(range(sv[1], sv[1] + 0x40)) | set(range(boot, boot + 0x12))
    p.relocate(refs, ram_map_c0, 'RAM', skip=set(skip) | dead)
    p.relocate(refs, spr_map_c0, 'SPR', skip=dead)
    p.relocate(refs, lambda v: OKIA, 'OKI', coords=False)
    p.put(0, L(ram_map_c0(p.getl(0))), 'ssp')
    for s in sv: p.put(s, bytes.fromhex('4e75'), 'view2 save/restore off')
    p.put(fgc + 8, L(0x37ff), 'fg clear visible rows only')
    # OKI "wait until channel started" poll -> assume started
    h = p.find(bytes.fromhex('e84e0246000f1e39') + L(OKIA)); assert len(h) == 1, h
    p.put(h[0] + 6, bytes.fromhex('7eff4e714e71'), 'okiwait', force=True)
    for t in timers:
        for hh in p.find(L(t)):
            op = p.getw(hh - 2)
            if (op & 0xf1ff) == 0x1039:
                p.put(hh - 2, struct.pack('>H', 0x70ff | ((op >> 9) & 7) << 9) + bytes.fromhex('4e714e71'), 'timer')
                p.log.append('timer read %06x patched' % (hh - 2))
    # --- new code in the padding
    flagvar = ram_map_c0(0xc07064)
    code, sym = asm(name + '_dec', 'mw_decomp.s', dict(FLAGVAR=flagvar, BOOTRET=boot + 0x12))
    assert p.unpatched[PAD0:PAD0 + 0x800] == b'\0' * 0x800
    p.put(PAD0, code, 'decompressor')
    p.put(dec, bytes.fromhex('4ef9') + L(PAD0 + sym['decomp']), 'decomp hook')
    p.put(boot, bytes.fromhex('4ef9') + L(PAD0 + sym['bootclr']), 'boot clear hook')
    p.log.append('decompressor %06x -> %06x, bootclr %06x' % (dec, PAD0, PAD0 + sym['bootclr']))
    if not vertical: flip_patch(p, PAD0, sym)
    # --- sprite converter
    a = one(p, '23c000780010', 'ofs')
    assert p.getw(a - 12) == 0x2039 and p.getw(a - 6) == 0xd0b9, 'ofs pattern'
    ofs1, ofs2 = p.getl(a - 10), p.getl(a - 4)
    hook = one(p, '4ef801004e71', 'hook')
    v4 = p.getl(0x70)
    assert p.img[v4:v4 + 6] == bytes.fromhex('027cf8ff4eb9') and p.getw(v4 + 10) == 0x4e73, 'irq4 handler'
    irq4fn = p.getl(v4 + 6)
    conv_addr = (PAD0 + len(code) + 0x1f) & ~0xf
    p.converter(hook, 0x100, ofs1, ofs2, addr=conv_addr, irq4fn=irq4fn, yoff=yoff, pad=b'\0',
                bufs=dict(SHADOW=SHADOW_C0, FLAGS=FLAGS_C0, MARK=MARK_C0))
    p.log.append('converter at %06x, IRQ4 routine %06x' % (conv_addr, irq4fn))
    p.save_image()
    return p.mra(title, setname, list(zips), oki, [spr], dips, rotate_vertical=vertical, year=year,
                 manufacturer=manufacturer, comment=';\n     picture decompressor rewritten to use the bitmap as its window')
