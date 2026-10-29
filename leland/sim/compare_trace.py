import os, re, sys

def load_dump(path):
    """Parse a MAME `dasm` output file into {addr: [opcode bytes]}."""
    instrs = {}
    pat = re.compile(r'^([0-9A-Fa-f]{4}):\s+([0-9A-Fa-f ]+?)\s{2,}')
    with open(path) as f:
        for line in f:
            m = pat.match(line)
            if not m:
                continue
            addr = int(m.group(1), 16)
            byte_str = m.group(2).strip()
            bytes_ = [int(b, 16) for b in byte_str.split()]
            instrs[addr] = bytes_
    return instrs

def collapse_sim_trace(path, limit=None):
    """Collapse sim's raw per-cycle (addr,byte) samples into one byte per
    contiguous run of identical addr (keeps the LAST/settled sample)."""
    out = []
    last_addr = None
    last_byte = None
    n = 0
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or ':' not in line:
                continue
            a, b = line.split(':')
            a = a.strip()
            b = b.strip()
            if b == 'xx':
                continue
            addr = int(a, 16)
            byte = int(b, 16)
            if addr != last_addr:
                if last_addr is not None:
                    out.append((last_addr, last_byte))
                    n += 1
                    if limit and n >= limit:
                        return out
                last_addr = addr
            last_byte = byte
        if last_addr is not None:
            out.append((last_addr, last_byte))
    return out

def m1_byte_stream_from_dump(dump, start_addr, count):
    """Walk the static dump starting at start_addr for `count` M1 fetches,
    following straight-line addresses only (no branches) -- used just to
    sanity check the very first boot bytes against a known-linear run."""
    out = []
    addr = start_addr
    for _ in range(count):
        if addr not in dump:
            break
        out.append(dump[addr][0])
        addr += len(dump[addr])
    return out

def collapse_loops(seq, min_run=3):
    """Collapse consecutive repeats of the same short cycle (e.g. an
    LDIR's ED,B0 M1 refetch) into one line + a repeat count, mirroring
    MAME's own '(loops for N instructions)' trace convention."""
    out = []
    i = 0
    n = len(seq)
    while i < n:
        matched = False
        for period in (1, 2, 3, 4):
            if i + period * 2 > n:
                continue
            block = seq[i:i+period]
            reps = 1
            j = i + period
            while j + period <= n and seq[j:j+period] == block:
                reps += 1
                j += period
            if reps >= min_run:
                out.append((block, reps))
                i = j
                matched = True
                break
        if not matched:
            out.append(([seq[i]], 1))
            i += 1
    return out

if __name__ == '__main__':
    base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    dump = load_dump(f'{base}/docs/reference/mame/traces/masterdump.asm')
    sim = collapse_sim_trace(f'{base}/sim/master_pc_trace.log')

    print(f'Loaded {len(dump)} static instructions from masterdump.asm')
    print(f'Collapsed sim trace to {len(sim)} settled (addr,byte) samples')
    print()

    compact = collapse_loops(sim)
    print(f'Loop-collapsed to {len(compact)} entries')
    print()
    print('First 150 loop-collapsed entries (addr:byte x count):')
    for block, reps in compact[:150]:
        items = ' '.join(f'{a:04x}:{b:02x}' for a, b in block)
        print(f'  [{items}] x{reps}')
