import struct,sys
import os
R=os.environ.get('COMAD_ROMS', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'roms')) + '/'
def il(e,o):
  a=open(R+e,'rb').read(); b=open(R+o,'rb').read(); r=bytearray(len(a)*2); r[0::2]=a; r[1::2]=b; return bytes(r)
def image(banks):
  return b''.join(il(e,o) for e,o in banks)
M=0xffffffff
def rol32(x,n): return ((x<<n)|(x>>(32-n)))&M
def swap(x): return ((x<<16)|(x>>16))&M
def decomp(mem, base, idx, win=0x8000):
  rw=lambda a: struct.unpack('>H',mem[a:a+2])[0]
  rl=lambda a: struct.unpack('>I',mem[a:a+4])[0]
  a0=base+((idx*4)&255); off=rl(a0); a0=base+off+8
  width=rl(a0-4)>>16
  d3=0; d4=0
  def mw(): nonlocal a0,d3; d3=(d3&0xffff0000)|rw(a0); a0+=2
  mw()
  pos=0; maxd=0; n=0; d2=0
  def fetch():   # 39c64
    nonlocal d3
    if d4==0: mw()
    elif d4==1: d3=rol32(d3,4); d3=swap(d3); mw(); d3=swap(d3); d3=rol32(d3,8); d3=rol32(d3,4)
    elif d4==2: d3=rol32(d3,8); d3=swap(d3); mw(); d3=swap(d3); d3=rol32(d3,8)
    elif d4==3: d3=rol32(d3,8); d3=rol32(d3,4); d3=swap(d3); mw(); d3=swap(d3); d3=rol32(d3,4)
    else: mw(); d3=swap(d3)
  def nib():     # 39c12
    nonlocal d3,d4
    if d4==0: d3=swap(d3); mw(); d3=swap(d3); d3=rol32(d3,4); d4=3
    elif d4==1: d3=rol32(d3,4); d4=0
    elif d4==2: d3=rol32(d3,4); d4=1
    elif d4==3: d3=rol32(d3,4); d4=2
    else: d3=rol32(d3,4); d4=3
  while True:
    w=d3&0xffff; cmd=w>>14
    if cmd<2:
      d2=(w<<1)&0xffff; pos+=1; n+=1; fetch()
    elif cmd==2:
      ref=(w<<1)&0x7fff; fetch(); w=d3&0xffff; cnt=w>>12
      if cnt==0: break
      dist=((pos*2-ref)&0x7fff); maxd=max(maxd,dist if dist else 0x8000)
      pos+=cnt+1; n+=cnt+1; nib()
    else:
      cnt=(w>>12)&3; pos+=cnt+1; n+=cnt+1; nib()
  return width,n,maxd,a0
if __name__=='__main__':
  mem=image([('missw96/mw96_10.bin','missw96/mw96_06.bin'),('missw96/mw96_09.bin','missw96/mw96_05.bin'),('missw96/mw96_08.bin','missw96/mw96_04.bin'),('missw96/mw96_07.bin','missw96/mw96_03.bin')])
  for base,cnt in ((0x28248c,64),(0x3be220,2)):
    seen=set()
    for i in range(cnt):
      off=struct.unpack('>I',mem[base+i*4:base+i*4+4])[0]
      if off in seen or off>0x400000: continue
      seen.add(off)
      try: print(hex(base),i,hex(off),decomp(mem,base,i))
      except Exception as e: print(hex(base),i,'ERR',e)
