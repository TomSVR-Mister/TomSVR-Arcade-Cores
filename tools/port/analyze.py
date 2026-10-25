#!/usr/bin/env python3
"""Generic analysis of a Comad/expro02 game for porting to jtgals.
usage: analyze.py <driver> <prog_image.bin> <ram_lo,ram_hi[;lo,hi..]> [frames]
Runs the original game in MAME (driver) to collect: code coverage, RAM page usage,
hidden bitmap row usage, sprite usage; then statically classifies address references."""
import sys, os, subprocess, struct, re, json
BASE = os.path.dirname(os.path.abspath(__file__))   # tools/port
drv, progbin, ramspec = sys.argv[1], sys.argv[2], sys.argv[3]
frames = int(sys.argv[4]) if len(sys.argv) > 4 else 9000
RAM = [tuple(int(x, 16) for x in r.split(',')) for r in ramspec.split(';')]
OUT = f'{BASE}/an_{drv}'
ODT = '/tmp/od_%d.bin' % os.getpid()
os.makedirs(OUT, exist_ok=True)

lua = r'''
local sp = manager.machine.devices[":maincpu"].spaces["program"]
local cov, ram, hid = {}, {}, {}
TAPS = {}
TAPS[#TAPS+1] = sp:install_read_tap(0x000000, 0x0fffff, "cov", function(o,d,m) cov[o >> 6] = true; return d end)
for _, r in ipairs(RAMRANGES) do
  TAPS[#TAPS+1] = sp:install_read_tap(r[1], r[2], "rr", function(o,d,m) local k=o>>8; ram[k]=(ram[k] or 0)+1; return d end)
  TAPS[#TAPS+1] = sp:install_write_tap(r[1], r[2], "rw", function(o,d,m) local k=o>>8; ram[k]=(ram[k] or 0)+1; return d end)
end
TAPS[#TAPS+1] = sp:install_write_tap(0x538000, 0x53ffff, "hb", function(o,d,m) local k=o>>8; hid[k]=(hid[k] or 0)+1; return d end)
TAPS[#TAPS+1] = sp:install_write_tap(0x518000, 0x51ffff, "hf", function(o,d,m) local k=o>>8; hid[k]=(hid[k] or 0)+1; return d end)
local spr = {}
local n = 0
local function press(port, field, v)
  local p = manager.machine.ioport.ports[port]; if not p then return end
  for nm, f in pairs(p.fields) do if nm == field then f:set_value(v) end end
end
emu.register_frame_done(function()
  n = n + 1
  local m = n % 3000
  if m == 1200 or m == 1240 then press(":SYSTEM", "Coin 1", 1) end
  if m == 1205 or m == 1245 then press(":SYSTEM", "Coin 1", 0) end
  if m == 1300 then press(":SYSTEM", "1 Player Start", 1) end
  if m == 1305 then press(":SYSTEM", "1 Player Start", 0) end
  if m > 1320 then
    local dirs = {"P1 Up","P1 Down","P1 Left","P1 Right"}
    local ph = ((n // 37) + (n // 211)) % 4
    for i,dn in ipairs(dirs) do press(":DSW1", dn, (i-1)==ph and 1 or 0) end
    press(":DSW1", "P1 Button 1", ((n//23)%3~=0) and 1 or 0)
  end
  if n % 100 == 0 then
    for s=0,511 do
      local b = 0x700000 + s*8
      local a,c = sp:read_u16(b), sp:read_u16(b+2)
      if c ~= 0 then local k = string.format("%04x", a & 0xff03 | ((a>>2)&0xf)<<4 ); spr[k]=(spr[k] or 0)+1 end
    end
  end
  if n % 1000 == 0 then manager.machine.video:snapshot() end
  if n >= FRAMES then
    local f = io.open(OUTDIR.."/cov.txt","w"); for k,_ in pairs(cov) do f:write(string.format("%06x\n",k<<6)) end; f:close()
    f = io.open(OUTDIR.."/ram.txt","w"); for k,v in pairs(ram) do f:write(string.format("%06x %d\n",k<<8,v)) end; f:close()
    f = io.open(OUTDIR.."/hid.txt","w"); for k,v in pairs(hid) do f:write(string.format("%06x %d\n",k<<8,v)) end; f:close()
    f = io.open(OUTDIR.."/spr.txt","w"); for k,v in pairs(spr) do f:write(k.." "..v.."\n") end; f:close()
    manager.machine:exit()
  end
end)
'''
ranges = '{' + ','.join('{0x%x,0x%x}' % (lo, hi) for lo, hi in RAM) + '}'
open(f'{OUT}/an.lua', 'w').write(f'RAMRANGES={ranges}\nFRAMES={frames}\nOUTDIR="{OUT}"\n' + lua)
if not os.path.exists(f'{OUT}/cov.txt') or '--rerun' in sys.argv:
    env = dict(os.environ, PATH=os.environ['PATH'] + ':/usr/games', SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy')
    subprocess.run(['mame', drv, '-rompath', os.environ.get('MAME_ROMS', os.path.join(BASE, 'roms')), '-cfg_directory', f'{OUT}/cfg', '-nvram_directory', f'{OUT}/cfg',
                    '-snapshot_directory', f'{OUT}/snap', '-snapname', '%i',
                    '-video', 'none', '-sound', 'none', '-skip_gameinfo', '-nothrottle', '-autoboot_script', f'{OUT}/an.lua'],
                   env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3000)

d = open(progbin, 'rb').read()
# ---- code regions from coverage + decode quality
cov = sorted(int(x, 16) for x in open(f'{OUT}/cov.txt'))
regs = []
for a in cov:
    if regs and a - regs[-1][1] <= 0x400: regs[-1][1] = a + 0x40
    else: regs.append([a, a + 0x40])
def objdump(start, stop):
    open(ODT, 'wb').write(d)
    out = subprocess.run(['m68k-linux-gnu-objdump', '-D', '-b', 'binary', '-m', 'm68k:68000',
                          f'--start-address=0x{start:x}', f'--stop-address=0x{stop:x}', ODT],
                         capture_output=True, text=True).stdout
    ins = []
    for line in out.splitlines():
        m = re.match(r'\s+([0-9a-f]+):\t((?:[0-9a-f]{4} )+)\s*\t?(.*)', line)
        if m:
            t = m.group(3).strip()
            if t == '' and ins: continue
            ins.append((int(m.group(1), 16), t))
    res = []
    for k, (a, t) in enumerate(ins):
        n = (ins[k + 1][0] if k + 1 < len(ins) else stop) - a
        res.append((a, n, t))
    return res
code = []
for s, e in regs:
    s = max(s, 0x100)
    ins = objdump(s, e)
    bad = sum(1 for a, n, t in ins if t.startswith('.short') or 'illegal' in t)
    rts = sum(1 for a, n, t in ins if t in ('rts', 'rte'))
    kind = 'CODE' if (rts > 0 and bad <= max(4, len(ins) * 0.05)) else 'data'
    print(f'region {s:06x}-{e:06x} insn={len(ins)} bad={bad} rts={rts} -> {kind}')
    if kind == 'CODE': code.append([s, e])
# extend code regions forward/backward while decode stays clean (unexecuted code)
def clean(a0, a1):
    ins = objdump(a0, a1)
    return sum(1 for a, n, t in ins if t.startswith('.short') or 'illegal' in t) <= 1 and len(ins) > 20
for r in code:
    while r[1] < 0x100000 and clean(r[1], r[1] + 0x100): r[1] += 0x100
    while r[0] > 0x100 and clean(r[0] - 0x100, r[0]): r[0] -= 0x100
# merge
code.sort(); merged = []
for r in code:
    if merged and r[0] <= merged[-1][1] + 0x200: merged[-1][1] = max(merged[-1][1], r[1])
    else: merged.append(r)
print('CODE REGIONS', [(hex(a), hex(b)) for a, b in merged])

# ---- RAM usage (exclude pages only touched by boot clear: count <= 2*128)
ram = sorted((int(a, 16), int(c)) for a, c in (l.split() for l in open(f'{OUT}/ram.txt')))
used = [a for a, c in ram if c > 260]
uranges = []
for a in used:
    if uranges and a - uranges[-1][1] <= 0x100: uranges[-1][1] = a + 0x100
    else: uranges.append([a, a + 0x100])
print('RAM USED', [(hex(a), hex(b)) for a, b in uranges])
hid = sorted((int(a, 16), int(c)) for a, c in (l.split() for l in open(f'{OUT}/hid.txt')))
print('HIDDEN ROW writes >128:', [(hex(a), c) for a, c in hid if (0x53c000 <= a or 0x51c000 <= a < 0x520000) and c > 128][:20])
print('SPRITE attr(hi,flip)/color histogram:', open(f'{OUT}/spr.txt').read().replace('\n', ' ')[:600])

# ---- references
allins = []
for s, e in merged: allins += objdump(s, e)
json.dump({'code': merged, 'ram_used': uranges}, open(f'{OUT}/info.json', 'w'))
with open(f'{OUT}/code.asm', 'w') as f:
    for a, n, t in allins: f.write(f'{a:06x}: {t}\n')
print('wrote', f'{OUT}/code.asm', len(allins), 'insns')
