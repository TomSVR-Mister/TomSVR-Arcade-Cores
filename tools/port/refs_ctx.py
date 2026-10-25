"""Find RAM-like constants outside known code regions that sit inside cleanly decoding code.
usage: refs_ctx.py image.bin refs.json 'lo-hi:LAB,...' out.json [scan_lo scan_hi]"""
import sys,struct,subprocess,re,os,json
img,refsp,tspec,outp=sys.argv[1:5]
lo0,hi0=(int(sys.argv[5],16),int(sys.argv[6],16)) if len(sys.argv)>6 else (0x100,0x100000-4)
d=open(img,'rb').read()
T=[]
for t in tspec.split(','):
  rng,lab=t.split(':'); a,b=(int(x,16) for x in rng.split('-')); T.append((a,b,lab))
known={r['j'] for r in json.load(open(refsp))}
TMP='/tmp/rc_%d.bin'%os.getpid(); open(TMP,'wb').write(d)
def dis(s,e):
  out=subprocess.run(['m68k-linux-gnu-objdump','-D','-b','binary','-m','m68k:68000',f'--start-address=0x{s:x}',f'--stop-address=0x{e:x}',TMP],capture_output=True,text=True).stdout
  r=[]
  for l in out.splitlines():
    m=re.match(r'\s+([0-9a-f]+):\t((?:[0-9a-f]{4} )+)\s*\t?(.*)',l)
    if m and m.group(3).strip(): r.append((int(m.group(1),16),m.group(3).strip()))
  return r
OK=re.compile(r'^(lea|move|movea|cmp|tst|clr|btst|bset|bclr|bchg|add|sub|and|or|eor|neg|not|jsr|jmp|pea|mul|div|st|sf|lsl|lsr|asl|asr)')
res=[]
for j in range(lo0,hi0,2):
  v=struct.unpack('>I',d[j:j+4])[0]
  lab=[l for a,b,l in T if a<=v<b]
  if not lab or j in known: continue
  for back in (2,4,6,8,10):
    s0=j-back; ins=dis(s0,j+4)
    if not(ins and ins[0][0]==s0 and ('0x%x'%v in ins[0][1] or '#%d'%v in ins[0][1])): continue
    t=ins[0][1]
    if not OK.match(t) or (('#%d'%v) in t and not t.startswith(('moveal','movel','lea','cmpal'))): continue
    # context: forward 0x30 clean, and some start 0x20-0x40 before syncs to s0 cleanly
    fw=dis(s0,s0+0x30); fbad=0
    for a,x in fw[1:]:
      if x.startswith('.short') or 'illegal' in x: fbad=1; break
      if x in ('rts','rte') or x.startswith(('jmp','bras','braw')): break
    ok_back=False
    for st in range(s0-0x40,s0-0x1e,2):
      bw=dis(st,s0+2)
      if any(a==s0 for a,x in bw) and not any(x.startswith('.short') or 'illegal' in x for a,x in bw if a<s0): ok_back=True; break
    if fbad==0 or ok_back:
      res.append(dict(j=j,v=v,lab=lab[0],cls='covered',insn='%06x %s'%(s0,t)))
    break
json.dump(res,open(outp,'w'),indent=0)
from collections import Counter
print(len(res),Counter(r['lab'] for r in res))
regs=[]
for r in res:
  if regs and r['j']-regs[-1][1]<0x200: regs[-1][1]=r['j']; regs[-1][2]+=1
  else: regs.append([r['j'],r['j'],1])
print(' '.join('%x-%x:%d'%tuple(x) for x in regs))
