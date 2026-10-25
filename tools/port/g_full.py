import sys
from games_lzfull import build
import g_batch4 as B
EXTRA = {
  'wownfant':  dict(progfree=[(0xb9000, 0xc0000), (0xdbfc0, 0x100000)]),
  'wownfanta': dict(progfree=[(0xb9200, 0xc0000), (0xdc000, 0x100000)]),
  'missw02':   dict(progfree=[(0xb9000, 0xc0000), (0xdbfc0, 0x100000)]),
  'missw02d':  dict(progfree=[(0xb9000, 0xc0000), (0xdbfc0, 0x100000)]),
}
for g in (sys.argv[1:] or ['wownfant', 'wownfanta', 'missw02', 'missw02d']):
    a = dict(B.GAMES[g]); refs = 'refs4_%s.json' % a.pop('refs', g)
    a.update(EXTRA[g])
    try:
        print(build(g + '_full', a.pop('setname'), a.pop('title'), a.pop('banks'), a.pop('spr'), a.pop('oki'), refs, a.pop('zips'), **a))
    except AssertionError as e:
        if 'does not fit' not in str(e): raise
        print(g, 'does not fit with all original faces (%s): drawing the small faces from the large ones' % e)
        a = dict(B.GAMES[g]); a.update(EXTRA[g])
        print(build(g + '_full', a.pop('setname'), a.pop('title'), a.pop('banks'), a.pop('spr'), a.pop('oki'), refs, a.pop('zips'), derive40=True, **a))
