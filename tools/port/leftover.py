import struct,subprocess,re,sys,os
d=open(sys.argv[1],'rb').read(); lo,hi=int(sys.argv[2],16),int(sys.argv[3],16)
T='/tmp/lo_%d.bin'%os.getpid(); open(T,'wb').write(d)
def dis(s,e):
  out=subprocess.run(['m68k-linux-gnu-objdump','-D','-b','binary','-m','m68k:68000',f'--start-address=0x{s:x}',f'--stop-address=0x{e:x}',T],capture_output=True,text=True).stdout
  r=[]
  for l in out.splitlines():
    m=re.match(r'\s+([0-9a-f]+):\t((?:[0-9a-f]{4} )+)\s*\t?(.*)',l)
    if m and m.group(3).strip(): r.append((int(m.group(1),16),m.group(3).strip()))
  return r
for j in range(0,0x100000,2):
  v=struct.unpack('>I',d[j:j+4])[0]
  if lo<=v<hi:
    why=''
    for b in (2,4,6,8,10):
      ins=dis(j-b,j+4)
      if ins and ins[0][0]==j-b and ('0x%x'%v in ins[0][1] or '#%d'%v in ins[0][1]): why='%06x %s'%(j-b,ins[0][1]); break
    print('%06x %08x %s | %s'%(j,v,d[j-4:j+6].hex(' ',2),why))
