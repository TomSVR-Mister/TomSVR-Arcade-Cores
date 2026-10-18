# pa_best.py simdir refdir first step last rot(cw|none) out
import sys, os, numpy as np
from PIL import Image
simdir, refdir, first, step, last, rot, out = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5]), sys.argv[6], sys.argv[7]
sims = {int(f[6:11]): f for f in os.listdir(simdir) if f.endswith('.png')}
keys = sorted(sims)
def lsim(k):
    im = Image.open(f'{simdir}/{sims[k]}').convert('RGB')
    if rot == 'cw': im = im.rotate(-90, expand=True)
    if rot == 'ccw': im = im.rotate(90, expand=True)
    return np.asarray(im).astype(int)
rows = []
for i, t in enumerate(range(first, last + 1, step)):
    p = f'{refdir}/{i:04d}.png'
    if not os.path.exists(p): break
    b = np.asarray(Image.open(p).convert('RGB')).astype(int)
    best = None
    for k in keys:
        if abs(k - t) > int(os.environ.get("WIN","30")): continue
        a = lsim(k)
        a = a[:b.shape[0]]
        if a.shape[1] != b.shape[1]: continue
        t0 = int(os.environ.get("TOP","0")) if a.shape != b.shape else 0
        bb = b[t0:t0+a.shape[0]]
        if a.shape[0] < b.shape[0]: a = np.concatenate([a, np.zeros((b.shape[0]-a.shape[0],)+a.shape[1:],int)],0); bb=b
        d = int((np.abs(a - bb).sum(2) > 24).sum())
        if best is None or d < best[0]: best = (d, k, a)
    if best is None: continue
    print(f'{t}:{best[1]}:{best[0]}', end=' ')
    m = np.abs(best[2] - b).sum(2) > 24; dm = np.zeros_like(b); dm[m] = 255
    rows.append(np.concatenate([best[2], b, dm], 1))
print()
sel = rows[::max(1, len(rows)//6)][:6]
Image.fromarray(np.concatenate(sel, 0).astype(np.uint8)).save(out)
