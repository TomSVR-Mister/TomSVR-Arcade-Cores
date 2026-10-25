import sys,capstone as cs
d=open(sys.argv[1],'rb').read(); end=int(sys.argv[3],16)
md=cs.Cs(cs.CS_ARCH_M68K,cs.CS_MODE_BIG_ENDIAN|cs.CS_MODE_M68K_000)
a=0x100; out=open(sys.argv[2],'w'); bad=0
while a<end:
    i=next(md.disasm(d[a:a+12],a),None)
    if i is None: out.write(f'{a:06x}: dc.w ${d[a]<<8|d[a+1]:04x}\n'); a+=2; bad+=1; continue
    out.write(f'{a:06x}: {i.mnemonic} {i.op_str}\n'); a+=i.size
print('undecodable words',bad)
