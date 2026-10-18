import sys
def load(fn, lim=10**9):
    out=[]
    with open(fn) as f:
        for n,l in enumerate(f):
            if n>=lim: break
            out.append((int(l.split(':')[0],16), l.rstrip()))
    return out
m=load(sys.argv[1]); r=load(sys.argv[2])
W=24; i=j=0; ev=0
while i<len(m)-W and j<len(r)-W:
    if m[i][0]==r[j][0]: i+=1; j+=1; continue
    # try resync
    found=None
    for d in range(1,4000):
        if [x[0] for x in m[i:i+W]]==[x[0] for x in r[j+d:j+d+W]]: found=(0,d); break
        if [x[0] for x in m[i+d:i+d+W]]==[x[0] for x in r[j:j+W]]: found=(d,0); break
    ev+=1
    if found is None or ev>int(sys.argv[3] if len(sys.argv)>3 else 30):
        print('HARD divergence', i, j)
        for k in range(-12,14): print(f'{m[i+k][1]:46s} | {r[j+k][1]}')
        break
    print(f'resync at m{i} r{j}: skip m+{found[0]} r+{found[1]}  ({m[i][1]} | {r[j][1]})')
    i+=found[0]; j+=found[1]
else: print('end', i, j)
