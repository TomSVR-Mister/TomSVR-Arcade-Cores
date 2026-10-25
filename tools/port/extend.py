import sys,subprocess,re,os
img=sys.argv[1]; regs=[[int(x,16) for x in r.split('-')] for r in open(sys.argv[2]).read().strip().split(',')]
T='/tmp/ext_%d.bin'%os.getpid(); open(T,'wb').write(open(img,'rb').read())
def bad(s,e,lo=None):
  lo = s if lo is None else lo
  out=subprocess.run(['m68k-linux-gnu-objdump','-D','-b','binary','-m','m68k:68000',f'--start-address=0x{s:x}',f'--stop-address=0x{e:x}',T],capture_output=True,text=True).stdout
  n=b=0
  for l in out.splitlines():
    m=re.match(r'\s+([0-9a-f]+):\t((?:[0-9a-f]{4} )+)\s*\t?(.*)',l)
    if m and m.group(3).strip():
      if int(m.group(1),16)<lo: continue
      n+=1; t=m.group(3)
      if t.startswith('.short') or 'illegal' in t: b+=1
  return b,n
STEP=0x40
for r in regs:
  while r[1]<0x100000:
    b,n=bad(r[1]-0x20,r[1]+STEP,r[1])
    if b>0 or n<8: break
    r[1]+=STEP
  while r[0]>0x100:
    b,n=bad(r[0]-STEP-0x20,r[0],r[0]-STEP)
    if b>0 or n<8: break
    r[0]-=STEP
regs.sort(); out=[]
for a,b in regs:
  if out and a<=out[-1][1]+0x40: out[-1][1]=max(out[-1][1],b)
  else: out.append([a,b])
print(','.join('%x-%x'%(a,b) for a,b in out))
