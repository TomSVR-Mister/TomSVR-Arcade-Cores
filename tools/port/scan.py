import sys,re,struct,capstone as cs
d=open(sys.argv[1],'rb').read()
END=int(sys.argv[2],16)
md=cs.Cs(cs.CS_ARCH_M68K,cs.CS_MODE_BIG_ENDIAN|cs.CS_MODE_M68K_000)
ins=[]; a=0x100
while a<END:
    i=next(md.disasm(d[a:a+12],a),None)
    if i is None: ins.append((a,2,None,None)); a+=2; continue
    ins.append((a,i.size,i.mnemonic,i.op_str)); a+=i.size
# run-length of valid decode around each insn
valid=[x[2] is not None for x in ins]
runok=[False]*len(ins)
for k in range(len(ins)):
    lo=max(0,k-6); hi=min(len(ins),k+7)
    runok[k]=all(valid[lo:hi])
cands=[]; covered=set()
for k,(a,sz,mn,op) in enumerate(ins):
    if mn is None: continue
    for m in re.finditer(r'(#?)\$([0-9a-f]+)(?:\.[lw])?',op):
        v=int(m.group(2),16)
        if 0xc80000<=v<=0xc8ffff:
            raw=d[a:a+sz]; pat=struct.pack('>I',v)
            offs=[j for j in range(2,sz-3,2) if raw[j:j+4]==pat]
            cands.append(dict(a=a,mn=mn,op=op,v=v,imm=bool(m.group(1)),offs=offs,ok=runok[k]))
            for j in offs: covered.add(a+j)
print('candidates',len(cands),'not-in-clean-run',sum(1 for c in cands if not c['ok']),'no-byte-match',sum(1 for c in cands if not c['offs']))
for c in cands:
    if not c['ok'] or not c['offs'] or c['imm']:
        print(f"{c['a']:06x} {'IMM' if c['imm'] else 'ABS'} {'' if c['ok'] else 'NOISY'} {c['mn']} {c['op']} offs={c['offs']}")
# data scan whole program region for c8 longs not covered
extra=[j for j in range(0,0x100000,2) if 0xc80000<=struct.unpack('>I',d[j:j+4])[0]<=0xc8ffff and j not in covered]
print('uncovered c8 longs in 0-0xfffff:',len(extra))
for j in extra[:80]: print(f'  {j:06x}: {struct.unpack(">I",d[j:j+4])[0]:08x}')
import json; json.dump(cands,open(sys.argv[3],'w'))
