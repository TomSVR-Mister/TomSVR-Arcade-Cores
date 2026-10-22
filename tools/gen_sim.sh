#!/bin/bash
# gen_sim.sh <core> <set> <hdrlen> <cut1> [cut2] [cut3] : sim dir from $J/rom/<set>.rom
# LARGE=1 for JTFRAME_SDRAM_LARGE cores: 16 MB banks, words stored the way jtframe_sdram64_bank addresses them
# (column = {addr[22], addr[8:0]}, row = addr[21:9]), since the C++ model reads the files as row<<10 | column.
J=${J:-/home/claude/jtcores}   # jtcores checkout, with rom/<set>.rom
C=$1; SET=$2; H=$3; shift 3
D=$J/cores/$C/ver/$SET; mkdir -p $D; cd $D
ln -sf ../../../../rom/$SET.rom rom.bin
LARGE=${LARGE:-0} python3 - $J/rom/$SET.rom $H "$@" <<'PY'
import sys, os
large = os.environ.get('LARGE') == '1'
BL = 0x1000000 if large else 0x800000
d = open(sys.argv[1],'rb').read()[int(sys.argv[2]):]
sw = bytearray(len(d)); sw[0::2] = d[1::2]; sw[1::2] = d[0::2]
cuts = [0] + [int(x, 0) for x in sys.argv[3:]] + [len(d)]
while len(cuts) < 5: cuts.append(len(d))
for b in range(4):
    x = bytes(sw[cuts[b]:cuts[b+1]]); x += b'\xff' * (BL - len(x))
    if large:   # word a -> model word (a[21:9] << 10) | (a[22] << 9) | a[8:0]
        y = bytearray(BL)
        for a in range(0, BL // 2, 512):
            m = ((a >> 9) & 0x1fff) << 10 | ((a >> 22) & 1) << 9
            y[2*m:2*m+1024] = x[2*a:2*a+1024]
        x = bytes(y)
    open(f'sdram_bank{b}.bin','wb').write(x)
PY
cat > run.sh <<EOR
#!/bin/bash
export JTROOT=$J JTFRAME=$J/modules/jtframe
cd $J && source modules/jtframe/bin/setprj.sh >/dev/null 2>&1
cd $D && rm -rf .jtsim.lock && jtsim -video \${1:-400} \${2:-play.cab} \$3 \$4 \$5 \$6 > sim.log 2>&1
EOR
chmod +x run.sh
