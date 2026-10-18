# shiftfind.py simpng refpng rot : best (dx,dy) such that sim shifted matches ref
import sys, numpy as np
from PIL import Image
a = Image.open(sys.argv[1]).convert('RGB')
if sys.argv[3]=='ccw': a=a.rotate(90,expand=True)
if sys.argv[3]=='cw': a=a.rotate(-90,expand=True)
a=np.asarray(a).astype(int); b=np.asarray(Image.open(sys.argv[2]).convert('RGB')).astype(int)
h=min(a.shape[0],b.shape[0]); a=a[:h]; b=b[:h]
res=[]
for dy in range(-4,5):
  for dx in range(-4,5):
    s=np.roll(np.roll(a,dy,0),dx,1)
    d=(np.abs(s[8:-8,8:-8]-b[8:-8,8:-8]).sum(2)>24).sum(); res.append((d,dx,dy))
print(sorted(res)[:3])
