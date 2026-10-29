"""
Structural diff between our sim's raw PC trace and MAME's real captured
execution trace, to find the first point where our RTL's control flow
diverges from real hardware.

Real traces (docs/reference/mame/traces/mastertrace.log, slavetrace.log; local MAME captures, not in the repo)
are MAME debugger `trace` output: one "XXXX: mnemonic" line per executed
instruction, with repeated loops compressed to a single
"(loops for N instructions)" marker instead of literally repeating N
times. Our own traces (sim/master_pc_trace.log, slave_pc_trace.log) are
raw addresses tapped directly off the tv80 core's internal PC register,
one per instruction boundary, fully uncompressed.

Comparing these directly is apples-to-oranges (one is compressed, one
isn't, and loop iteration counts will legitimately differ between a
real board and our sim due to timing differences). So instead of trying
to expand MAME's compression byte-for-byte, this reduces BOTH sides to
a "structural" sequence -- consecutive repeats of the same short cycle
collapsed to one instance -- and diffs THAT. This is robust to
iteration-count differences and highlights the first place where our
sim visits a genuinely different address/region than real execution
ever did.
"""
import os
import re
import sys

LINE_RE = re.compile(r'^([0-9A-Fa-f]{4,6}):\s')


def parse_real_trace_structural(path):
    """Real MAME trace -> structural sequence: one entry per distinct
    instruction address the FIRST time it's seen in a run of new
    addresses; consecutive repeats and "(loops for N)" compressed runs
    both collapse away, since the loop body was already emitted once
    just before the marker."""
    out = []
    last = None
    with open(path, errors='replace') as f:
        for line in f:
            m = LINE_RE.match(line)
            if not m:
                continue
            addr = int(m.group(1), 16)
            if addr != last:
                out.append(addr)
                last = addr
    return out


def parse_sim_trace_structural(path):
    """Our raw PC trace -> structural sequence: collapse consecutive
    repeats of the same short cycle (period 1..8) to one instance,
    mirroring how the real trace's loop compression already reads."""
    out = []
    i = 0
    seq = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            seq.append(int(line, 16))
    n = len(seq)
    last = None
    while i < n:
        matched = False
        for period in range(1, 9):
            if i + period * 2 > n:
                continue
            block = seq[i:i + period]
            j = i + period
            reps = 1
            while j + period <= n and seq[j:j + period] == block:
                reps += 1
                j += period
            if reps >= 3:
                for a in block:
                    if a != last:
                        out.append(a)
                        last = a
                i = j
                matched = True
                break
        if not matched:
            if seq[i] != last:
                out.append(seq[i])
                last = seq[i]
            i += 1
    return out


def find_first_divergence(real_seq, sim_seq, context=15, window=20000):
    """Alignment-based diff (difflib), not strict lockstep -- tolerant
    of benign insertions/deletions (e.g. MAME's trace command collapses
    ED/CB-prefixed opcodes to one line per instruction while our M1-
    gated sim trace shows both prefix-byte fetches separately) that
    would otherwise look like an immediate "divergence" on the very
    first prefixed opcode. Reports every non-trivial replace/delete/
    insert block in order, so real structural divergences (a genuinely
    different address, not just a convention mismatch) are easy to spot
    even if earlier benign mismatches exist. Runs on the first `window`
    entries of each side only -- full-sequence LCS on 700k+/100k+ entries
    is too slow; this is plenty to find the first real bug.
    """
    import difflib
    a = real_seq[:window]
    b = sim_seq[:window]
    sm = difflib.SequenceMatcher(a=a, b=b, autojunk=False)
    reported = 0
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == 'equal':
            continue
        # Skip tiny insert/delete blocks (<=2 entries) -- these are the
        # expected ED/CB-prefix-byte convention noise, not real bugs.
        if tag in ('insert', 'delete') and max(i2 - i1, j2 - j1) <= 2:
            continue
        reported += 1
        lo_i = max(0, i1 - context)
        lo_j = max(0, j1 - context)
        print(f'--- {tag} block #{reported}: real[{i1}:{i2}] vs sim[{j1}:{j2}] ---')
        print(f'  context before (real): {[hex(x) for x in a[lo_i:i1]]}')
        print(f'  context before (sim):  {[hex(x) for x in b[lo_j:j1]]}')
        print(f'  real[{i1}:{i2}] = {[hex(x) for x in a[i1:i2]][:40]}')
        print(f'  sim [{j1}:{j2}] = {[hex(x) for x in b[j1:j2]][:40]}')
        print(f'  real continues: {[hex(x) for x in a[i2:i2+context]]}')
        print(f'  sim  continues: {[hex(x) for x in b[j2:j2+context]]}')
        print()
        if reported >= 10:
            print('(stopping after 10 blocks)')
            break
    if reported == 0:
        print(f'No non-trivial divergence found in the first {window} structural entries of each trace.')


if __name__ == '__main__':
    which = sys.argv[1] if len(sys.argv) > 1 else 'master'
    base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if which == 'master':
        real_path = f'{base}/docs/reference/mame/traces/mastertrace.log'
        sim_path = f'{base}/sim/master_pc_trace.log'
    else:
        real_path = f'{base}/docs/reference/mame/traces/slavetrace.log'
        sim_path = f'{base}/sim/slave_pc_trace.log'

    print(f'Parsing real trace: {real_path}')
    real_seq = parse_real_trace_structural(real_path)
    print(f'  -> {len(real_seq)} structural entries')

    print(f'Parsing sim trace: {sim_path}')
    sim_seq = parse_sim_trace_structural(sim_path)
    print(f'  -> {len(sim_seq)} structural entries')
    print()

    find_first_divergence(real_seq, sim_seq)
