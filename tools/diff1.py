# diff1.py sim.png ref.png out.png [rot]
import sys, numpy as np
from PIL import Image
a = Image.open(sys.argv[1]).convert('RGB')
if len(sys.argv) > 4 and sys.argv[4] == 'ccw': a = a.rotate(90, expand=True)
a = np.asarray(a).astype(int); b = np.asarray(Image.open(sys.argv[2]).convert('RGB')).astype(int)
h = min(a.shape[0], b.shape[0]); a, b = a[:h], b[:h]
m = np.abs(a-b).sum(2) > 24
ys, xs = np.nonzero(m); print('diff', m.sum(), 'bbox', (xs.min(), ys.min(), xs.max(), ys.max()) if m.sum() else None)
d = np.zeros_like(a); d[m] = 255
im = np.concatenate([a, b, d], 1).astype(np.uint8)
Image.fromarray(im).resize((im.shape[1]*2, im.shape[0]*2), Image.NEAREST).save(sys.argv[3])
