import sys,re,struct,json,capstone as cs
d=open(sys.argv[1],'rb').read()
CODE=[(0x100,0x16c00),(0x35900,0x37500),(0x42e00,0x44100)]
USED=[(0xc80000,0xc82a00),(0xc87000,0xc87100),(0xc88000,0xc8a020),(0xc8f000,0xc90000)]
used=lambda v:any(a<=v<b for a,b in USED)
md=cs.Cs(cs.CS_ARCH_M68K,cs.CS_MODE_BIG_ENDIAN|cs.CS_MODE_M68K_000)
ins={}; starts=set()
for s,e in CODE:
    a=s
    while a<e:
        i=next(md.disasm(d[a:a+12],a),None)
        if i is None: a+=2; continue
        ins[a]=(i.size,i.mnemonic,i.op_str); starts.add(a); a+=i.size
covered={}
for a,(sz,mn,op) in ins.items():
    for m in re.finditer(r'(#?)\$([0-9a-f]+)(?:\.[lw])?',op):
        v=int(m.group(2),16)
        if 0xc80000<=v<=0xc8ffff:
            for j in range(2,sz-3,2):
                if d[a+j:a+j+4]==struct.pack('>I',v): covered[a+j]=(a,mn,op,bool(m.group(1)))
incode=lambda j:any(s<=j<e for s,e in CODE)
out=[]
for j in range(0,0x100000,2):
    v=struct.unpack('>I',d[j:j+4])[0]
    if not (0xc80000<=v<=0xc8ffff) or j in covered: continue
    # in code: skip windows that are imm-word + opcode (j+2 is an insn start, j inside previous insn)
    if incode(j) and (j+2) in starts and j not in starts: continue
    out.append((j,v,used(v),incode(j)))
for j,v,u,c in out:
    if u: print(f'{j:06x}: {v:08x} {"CODE" if c else "data"}  ctx: {d[j-8:j+12].hex(" ",2)}')
print('total uncovered',len(out),'in used ranges',sum(1 for x in out if x[2]))
json.dump({'covered':{str(k):v for k,v in covered.items()},'uncov':out},open(sys.argv[2],'w'))
