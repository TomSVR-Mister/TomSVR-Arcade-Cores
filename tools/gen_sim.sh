#!/bin/bash
# gen_sim.sh <core> <set> <hdrlen> <cut1> [cut2] [cut3] : sim dir from $J/rom/<set>.rom
S=/tmp/claude-0/-home-claude/e1042311-2b93-5281-bddb-91ed22183aec/scratchpad; J=$S/comad/jtcores
C=$1; SET=$2; H=$3; shift 3
D=$J/cores/$C/ver/$SET; mkdir -p $D; cd $D
ln -sf ../../../../rom/$SET.rom rom.bin
python3 - $J/rom/$SET.rom $H "$@" <<'PY'
import sys
d = open(sys.argv[1],'rb').read()[int(sys.argv[2]):]
sw = bytearray(len(d)); sw[0::2] = d[1::2]; sw[1::2] = d[0::2]
cuts = [0] + [int(x, 0) for x in sys.argv[3:]] + [len(d)]
while len(cuts) < 5: cuts.append(len(d))
for b in range(4):
    x = bytes(sw[cuts[b]:cuts[b+1]]); x += b'\xff' * (0x800000 - len(x))
    open(f'sdram_bank{b}.bin','wb').write(x)
PY
cat > run.sh <<EOR
#!/bin/bash
export JTROOT=$J JTFRAME=$J/modules/jtframe
cd $J && source modules/jtframe/bin/setprj.sh >/dev/null 2>&1
cd $D && rm -rf .jtsim.lock && jtsim -video \${1:-400} \${2:-play.cab} \$3 \$4 \$5 \$6 > sim.log 2>&1
EOR
chmod +x run.sh
