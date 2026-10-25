import sys
from port import COMAD
from games_lzfull import build
import g_batch4 as B
assert COMAD
for g in (sys.argv[1:] or ['fantsia2', 'fantsia2a', 'fantsia2n', 'wownfant', 'wownfanta', 'missw02', 'missw02d']):
    a = dict(B.GAMES[g]); refs = 'refs4_%s.json' % a.pop('refs', g)
    print(build(g, a.pop('setname'), a.pop('title'), a.pop('banks'), a.pop('spr'), a.pop('oki'), refs, a.pop('zips'), **a))
