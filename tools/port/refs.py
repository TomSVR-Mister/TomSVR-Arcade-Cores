#!/usr/bin/env python3
"""Classify every aligned 32-bit value inside code regions that falls in target ranges.
   covered : operand of an instruction in the linear objdump sweep
   desync  : not covered by the sweep, but decoding from j-2..j-10 yields an instruction whose operand it is
   data    : neither (table entry or coincidence) -> needs a decision
usage: refs.py image.bin 'lo-hi,lo-hi' 'tlo-thi:label,...' out.json"""
import sys, re, struct, subprocess, json, os
img, regspec, tspec, outp = sys.argv[1:5]
d = open(img, 'rb').read()
REG = [tuple(int(x, 16) for x in r.split('-')) for r in regspec.split(',')]
T = []
for t in tspec.split(','):
    rng, lab = t.split(':'); lo, hi = (int(x, 16) for x in rng.split('-')); T.append((lo, hi, lab))
TMP = '/tmp/rf_%d.bin' % os.getpid()
open(TMP, 'wb').write(d)
def objdump(start, stop):
    out = subprocess.run(['m68k-linux-gnu-objdump', '-D', '-b', 'binary', '-m', 'm68k:68000',
                          f'--start-address=0x{start:x}', f'--stop-address=0x{stop:x}', TMP],
                         capture_output=True, text=True).stdout
    ins = []
    for line in out.splitlines():
        m = re.match(r'\s+([0-9a-f]+):\t((?:[0-9a-f]{4} )+)\s*\t?(.*)', line)
        if m:
            t = m.group(3).strip()
            if t == '' and ins: continue          # continuation line of a long instruction
            ins.append([int(m.group(1), 16), 0, t])
    for k in range(len(ins)):
        ins[k][1] = (ins[k + 1][0] if k + 1 < len(ins) else stop) - ins[k][0]
    return ins
def has(t, v): return ('0x%x' % v) in t or re.search(r'#%d\b' % v, t) is not None
def lab(v):
    for lo, hi, l in T:
        if lo <= v < hi: return l
cov = {}
for s, e in REG:
    for a, n, t in objdump(s, e):
        for j in range(a + 2, a + n - 3, 2):
            v = struct.unpack('>I', d[j:j + 4])[0]
            if lab(v) and has(t, v): cov[j] = (a, t)
res = []
for s, e in REG:
    for j in range(s, e, 2):
        v = struct.unpack('>I', d[j:j + 4])[0]
        l = lab(v)
        if not l: continue
        if j in cov:
            res.append(dict(j=j, v=v, lab=l, cls='covered', insn='%06x %s' % cov[j])); continue
        cls, why = 'data', ''
        for back in (2, 4, 6, 8, 10):
            s0 = j - back
            ins = objdump(s0, j + 4)
            if ins and ins[0][0] == s0 and ins[0][1] >= back + 4 and has(ins[0][2], v):
                cls, why = 'desync', '%06x %s' % (s0, ins[0][2]); break
        res.append(dict(j=j, v=v, lab=l, cls=cls, insn=why, ctx=d[j - 6:j + 8].hex(' ', 2)))
json.dump(res, open(outp, 'w'), indent=0)
from collections import Counter
print(Counter((r['lab'], r['cls']) for r in res))
for r in res:
    if r['cls'] != 'covered':
        print(f"{r['cls']:6} {r['lab']:5} {r['j']:06x}: {r['v']:08x}  {r.get('ctx','')}  {r['insn']}")
