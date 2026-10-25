import sys
from games_lz import *
F = 'fantsia2/'; FA = F + 'fantsia2a/'; W = 'wownfant/'; M = 'missw02/'
def il4(files):   # [(even, odd)] for 0x100000.. banks
    return [(0x100000 * (i + 1), 'il', f) for i, f in enumerate(files)]
SCR = [(F + 'scr2.g16', F + 'scr1.f16'), (F + 'scr4.g15', F + 'scr3.f15'), (F + 'scr6.g14', F + 'scr5.f14'), (F + 'scr8.g20', F + 'scr7.f20')]
FNT = [(FA + 'fnt2-21.bin', FA + 'fnt2-16.bin'), (FA + 'fnt2-20.bin', FA + 'fnt2-15.bin'), (FA + 'fnt2-19.bin', FA + 'fnt2-14.bin'), (FA + 'fnt2-18.bin', FA + 'fnt2-13.bin')]
OKI2 = [F + 'music2.1b', F + 'music1.1a']
WOKI = [W + 'ep-4001 42750001 u4.u4', W + 'ep-4001 42750001 u1.u1']
MOKI = [M + 'u4', M + 'u1']
GAMES = {
  'fantsia2':  dict(setname='fantsia2', title='Fantasia II (Explicit)', banks=[(0, 'il', (F + 'prog2.g17', F + 'prog1.f17'))] + il4(SCR),
                    spr=[F + 'obj1.1i', F + 'obj2.2i'], oki=OKI2, zips=('fantsia2.zip',), year='1997'),
  'fantsia2a': dict(setname='fantsia2a', title='Fantasia II (Less Explicit)', banks=[(0, 'il', (FA + 'fnt2-22.bin', FA + 'fnt2-17.bin'))] + il4(FNT),
                    spr=[F + 'obj1.1i', F + 'obj2.2i'], oki=OKI2, zips=('fantsia2a.zip', 'fantsia2.zip'), year='1997'),
  'fantsia2n': dict(setname='fantsia2n', title='Fantasia II (1998)', banks=[(0, 'il', (F + 'prog2.g17', F + 'prog1.f17'))] + il4(SCR),
                    spr=[F + 'fantsia2n/23_obj1.u5', F + 'obj2.2i'], oki=OKI2, zips=('fantsia2n.zip', 'fantsia2.zip'), year='1998', refs='fantsia2'),
  'wownfant':  dict(setname='wownfant', title='WOW New Fantasia', banks=[(0, 'il', (W + 'ep-4001 42750001 u81.u81', W + 'ep-4001 42750001 u80.u80')),
                    (0x100000, 'ws', W + 'ep-061 43750002 - 1.bin'), (0x300000, 'ws', W + 'ep-061 43750002 - 2.bin')],
                    spr=[W + 'ep-4001 42750001 u113.u113', W + 'ep-4001 42750001 u112.u112'], oki=WOKI, zips=('wownfant.zip',), year='2002', manufacturer='Comad'),
  'wownfanta': dict(setname='wownfanta', title='WOW New Fantasia (Explicit)', banks=[(0, 'il', (W + 'wownfanta/2.u81', W + 'wownfanta/1.u80')),
                    (0x100000, 'ws', W + 'wownfanta/3.bin'), (0x300000, 'ws', W + 'wownfanta/4.bin')],
                    spr=[W + 'ep-4001 42750001 u113.u113', W + 'wownfanta/6.u112'], oki=WOKI, zips=('wownfanta.zip', 'wownfant.zip'), year='2002'),
  'missw02':   dict(setname='missw02', title='Miss World 2002', banks=[(0, 'il', (M + 'u81', M + 'u80')), (0x100000, 'ws', M + 'gfx1'), (0x300000, 'ws', M + 'gfx2')],
                    spr=[M + 'u113', M + 'u112'], oki=MOKI, zips=('missw02.zip',), year='2002', manufacturer='Daigom'),
  'missw02d':  dict(setname='missw02d', title='Miss World 2002 (Daigom license)', banks=[(0, 'il', (M + 'missw02d/8.u81', M + 'missw02d/7.u80')),
                    (0x100000, 'ws', M + 'gfx1'), (0x300000, 'ws', M + 'gfx2')],
                    spr=[M + 'u113', M + 'missw02d/5.u112'], oki=MOKI, zips=('missw02d.zip', 'missw02.zip'), year='2002', manufacturer='Daigom'),
}
def run(g):
    a = dict(GAMES[g]); refs = 'refs4_%s.json' % a.pop('refs', g)
    # how many girls fit? use the first half, try decreasing
    p = Port(g, a['banks'], 0x500000)
    out = []
    for part in ('A', 'B'):
        import games_lz, struct as st
        for K in range(30, 10, -1):
            try:
                kw = dict(a)
                # determine n from the program
                n = 36 if g.startswith(('wownfant', 'missw02')) else 35
                keep = list(range(K)) if part == 'A' else list(range(n - K, n))
                label = '%d-%d' % (keep[0] + 1, keep[-1] + 1)
                out.append(build('%s_%s' % (g, part), kw.pop('setname'), kw.pop('title'), kw.pop('banks'), kw.pop('spr'), kw.pop('oki'), refs,
                                 kw.pop('zips'), keep, label, **kw))
                break
            except AssertionError as e:
                if 'does not fit' not in str(e): raise
    return out
if __name__ == '__main__':
    for g in (sys.argv[1:] or GAMES):
        print(run(g))
