#!/usr/bin/env python3
"""Compare extracted pictures between sets of the same game.

usage: compare_pics.py PICDIR
Prints, per family, how many girl pictures each set has, how many are pixel
identical / perceptually the same as in the family's first set, and which are
unique. Writes PICDIR/compare.json.
"""
import os, sys, json, glob
import numpy as np
from PIL import Image

FAMILIES = {
 "Miss World '96": ['missw96', 'missw96a', 'missw96b', 'missw96c', 'missmw96', 'smissw'],
 'Super Model': ['supmodel', 'supmodl2'],
 'Zip & Zap': ['zipzap', 'zipzapa'],
 'Gals Hustler / Pocket Gals V.I.P.': ['galhustl', 'galhustla', 'pgalvipa', 'pgalvip'],
}

def sig(im):
    g = np.asarray(im.convert('L').resize((24, 24), Image.BILINEAR), np.float32)
    return (g - g.mean()) / (g.std() + 1e-6)

def load(d, s):
    out = []
    for f in sorted(glob.glob(os.path.join(d, s, '[0-9]*.png'))):
        im = Image.open(f).convert('RGB')
        out.append((os.path.basename(f), np.asarray(im), sig(im)))
    return out

def main():
    d = sys.argv[1]
    res = {}
    for fam, sets in FAMILIES.items():
        pics = {s: load(d, s) for s in sets}
        allp = [(s, f, a, g) for s in sets for f, a, g in pics[s]]
        # group perceptually equal pictures across the family
        groups = []
        for s, f, a, g in allp:
            for gr in groups:
                s0, f0, a0, g0 = gr[0]
                if np.abs(g - g0).mean() < 0.25:
                    gr.append((s, f, a, g)); break
            else:
                groups.append([(s, f, a, g)])
        print('==', fam, '-', len(groups), 'different pictures in total')
        fr = res[fam] = {'total_unique': len(groups), 'sets': {}}
        for s in sets:
            mine = [gr for gr in groups if any(x[0] == s for x in gr)]
            only = [gr for gr in mine if all(x[0] == s for x in gr)]
            ident = {}
            for t in sets:
                if t == s: continue
                same = sum(1 for gr in mine if any(x[0] == t for x in gr))
                exact = sum(1 for gr in mine for x in gr if x[0] == t and any(y[0] == s and y[2].shape == x[2].shape and (y[2] == x[2]).all() for y in gr))
                ident[t] = {'shared': same, 'pixel_identical': exact}
            fr['sets'][s] = {'pictures': len(pics[s]), 'only_in_this_set': [x[1] for gr in only for x in gr if x[0] == s], 'vs': ident}
            print('  %-10s %2d pictures, %2d only here; shared: %s' % (s, len(pics[s]), len(only),
                  ', '.join('%s %d (%d exact)' % (t, v['shared'], v['pixel_identical']) for t, v in ident.items())))
    json.dump(res, open(os.path.join(d, 'compare.json'), 'w'), indent=1)

if __name__ == '__main__':
    main()
