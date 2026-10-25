import struct
from lzemu import *
def decode_words(mem, base, idx, WW=16384):
  """full decode returning output words (raw window values) using the same token logic"""
  rw=lambda a: struct.unpack('>H',mem[a:a+2])[0]; rl=lambda a: struct.unpack('>I',mem[a:a+4])[0]
  a0=base+((idx*4)&255); start=a0; off=rl(a0); a0=((base+off)&0xffffffff)+8; hdr=mem[(base+off)&0xffffffff:((base+off)&0xffffffff)+8]
  st={'d3':0,'d4':0,'a0':a0}
  def mw(): st['d3']=(st['d3']&0xffff0000)|rw(st['a0']); st['a0']+=2
  def fetch():
    d4=st['d4']
    if d4==0: mw()
    elif d4==1: st['d3']=swap(rol32(st['d3'],4)); mw(); st['d3']=rol32(rol32(swap(st['d3']),8),4)
    elif d4==2: st['d3']=swap(rol32(st['d3'],8)); mw(); st['d3']=rol32(swap(st['d3']),8)
    elif d4==3: st['d3']=swap(rol32(rol32(st['d3'],8),4)); mw(); st['d3']=rol32(swap(st['d3']),4)
    else: mw(); st['d3']=swap(st['d3'])
  def nib():
    d4=st['d4']
    if d4==0: st['d3']=swap(st['d3']); mw(); st['d3']=rol32(swap(st['d3']),4); st['d4']=3
    else: st['d3']=rol32(st['d3'],4); st['d4']=d4-1 if d4<4 else 3
  mw(); out=[]; win=[0]*WW; d2=0
  while True:
    w=st['d3']&0xffff; cmd=w>>14
    if cmd<2: d2=(w<<1)&0xffff; win[len(out)%WW]=d2; out.append(d2); fetch()
    elif cmd==2:
      ref=w&0x3fff; fetch(); w=st['d3']&0xffff; cnt=w>>12
      if cnt==0: break
      for k in range(cnt+1): d2=win[(ref%WW+k)%WW]; win[len(out)%WW]=d2; out.append(d2)
      nib()
    else:
      cnt=(w>>12)&3
      for k in range(cnt+1): win[len(out)%WW]=d2; out.append(d2)
      nib()
  return out, hdr, st["a0"]-((base+off)&0xffffffff)
def encode(words, W):
  """optimal parse with window W words. returns token list"""
  n=len(words); INF=1<<30
  # match finder
  from collections import defaultdict
  heads=defaultdict(list); best=[None]*n
  for i in range(n):
    bl=0; bj=-1
    if i+1<n:
      key=(words[i],words[i+1]); cands=heads.get(key,[])
      for j in reversed(cands[-400:]):
        if i-j>=W: break
        l=0
        while l<16 and i+l<n and words[j+l]==words[i+l]: l+=1
        if l>bl: bl,bj=l,j
        if l==16: break
      heads[key].append(i)
    best[i]=(bl,bj)
  cost=[INF]*(n+1); prev=[None]*(n+1); cost[0]=0
  for i in range(n):
    c=cost[i]
    if c>=INF: continue
    # literal
    if words[i]&1==0:   # literal stores w<<1: value must have bit0 = 0
      if c+4<cost[i+1]: cost[i+1]=c+4; prev[i+1]=('L',i)
    bl,bj=best[i]
    for l in range(2,bl+1):
      if c+5<cost[i+l]: cost[i+l]=c+5; prev[i+l]=('C',bj,l)
    if i>0:
      k=0
      while k<4 and i+k<n and words[i+k]==words[i-1]: 
        k+=1
        if c+1<cost[i+k]: cost[i+k]=c+1; prev[i+k]=('R',k)
  toks=[]; i=n
  while i>0:
    p=prev[i]; toks.append(p)
    i-= 1 if p[0]=='L' else (p[2] if p[0]=='C' else p[1])
  toks.reverse(); return toks, cost[n]
def pack(toks, W):
  nibs=[]
  pos=0
  for t in toks:
    if t[0]=='L': v=t[1]; nibs+=[0]*0  # placeholder
  return None

def tokens_orig(mem, base, idx):
  """decode original stream into token list (L value)/(C ref14,len)/(R k)"""
  rw=lambda a: struct.unpack('>H',mem[a:a+2])[0]; rl=lambda a: struct.unpack('>I',mem[a:a+4])[0]
  off=rl(base+((idx*4)&255)); a0=((base+off)&0xffffffff)+8
  st={'d3':0,'d4':0,'a0':a0}
  def mw(): st['d3']=(st['d3']&0xffff0000)|rw(st['a0']); st['a0']+=2
  def fetch():
    d4=st['d4']
    if d4==0: mw()
    elif d4==1: st['d3']=swap(rol32(st['d3'],4)); mw(); st['d3']=rol32(rol32(swap(st['d3']),8),4)
    elif d4==2: st['d3']=swap(rol32(st['d3'],8)); mw(); st['d3']=rol32(swap(st['d3']),8)
    elif d4==3: st['d3']=swap(rol32(rol32(st['d3'],8),4)); mw(); st['d3']=rol32(swap(st['d3']),4)
    else: mw(); st['d3']=swap(st['d3'])
  def nib():
    d4=st['d4']
    if d4==0: st['d3']=swap(st['d3']); mw(); st['d3']=rol32(swap(st['d3']),4); st['d4']=3
    else: st['d3']=rol32(st['d3'],4); st['d4']=d4-1 if d4<4 else 3
  mw(); toks=[]
  while True:
    w=st['d3']&0xffff; cmd=w>>14
    if cmd<2: toks.append(('L',w)); fetch()
    elif cmd==2:
      ref=w&0x3fff; fetch(); cnt=(st['d3']&0xffff)>>12; toks.append(('C',ref,cnt+1))
      if cnt==0: break
      nib()
    else: toks.append(('R',((w>>12)&3)+1)); nib()
  return toks, st["a0"]-((base+off)&0xffffffff)-8
def pack_nibbles(toks):
  nb=[]
  for t in toks:
    if t[0]=='L': v=t[1]; nb+=[v>>12,(v>>8)&15,(v>>4)&15,v&15]
    elif t[0]=='C': v=0x8000|t[1]; nb+=[v>>12,(v>>8)&15,(v>>4)&15,v&15,(t[2]-1)&15]
    else: nb.append(0xc|(t[1]-1))
  while len(nb)%4: nb.append(0)
  return bytes(((nb[i]<<4)|nb[i+1]) for i in range(0,len(nb),2))
