"""Compare master I/O traces (MAME Lua vs RTL bench), ignoring PCs and timing.

usage: python compare_io.py mame_ataxx_io.log run_ax.log
Compares the per-port data sequences (writes and reads separately), so interrupt timing
differences between the two sims do not show up as divergences. Reports the first mismatch
per port and how many entries matched.
"""
import re, sys
from collections import defaultdict

pat = re.compile(r'(MIOWR|MIORD) #\d+ port=([0-9a-f]{2}) data=([0-9a-f]{2})')

def load(path):
    d = {"MIOWR": defaultdict(list), "MIORD": defaultdict(list)}
    for line in open(path, errors="replace"):
        m = pat.search(line)
        if m:
            d[m.group(1)][m.group(2)].append(m.group(3))
    return d

a = load(sys.argv[1])
b = load(sys.argv[2])

for kind in ("MIOWR", "MIORD"):
    print("==", "writes" if kind == "MIOWR" else "reads")
    for port in sorted(set(a[kind]) | set(b[kind])):
        x, y = a[kind][port], b[kind][port]
        n = min(len(x), len(y))
        bad = next((i for i in range(n) if x[i] != y[i]), None)
        if bad is None:
            print("  %s: %d compared, match (mame %d, rtl %d)" % (port, n, len(x), len(y)))
        else:
            print("  %s: MISMATCH at #%d mame=%s rtl=%s (mame ctx %s / rtl ctx %s)" %
                  (port, bad + 1, x[bad], y[bad], x[max(0, bad - 2):bad + 3], y[max(0, bad - 2):bad + 3]))
