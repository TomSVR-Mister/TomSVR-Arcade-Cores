import os,re,struct,sys
def face_tables(d, rb=0xf80000, hi=0x3e000):
    """tables of image routines that are called with a girl number (rb+0x7005 or the select list rb+0x7012..)"""
    res = {}
    for m in re.finditer(re.escape(bytes.fromhex('4e71e54822710000323c')), d[:hi]):
        i = m.start(); entry = i - 4
        tab = i - 2 + struct.unpack('>h', d[i - 2:i])[0]
        calls = [c for c in range(0, hi, 2) if (d[c:c+2] == b'\x61\x00' and c + 2 + struct.unpack('>h', d[c+2:c+4])[0] == entry)
                 or d[c:c+6] == b'\x4e\xb9' + struct.pack('>I', entry)]
        girl = 0
        for c in calls:
            ctx = d[max(0, c - 16):c]
            for k in range(len(ctx) - 5):
                if ctx[k:k+2] == b'\x10\x39' or ctx[k:k+2] == b'\x1c\x39':
                    a = struct.unpack('>I', ctx[k+2:k+6])[0]
                    if a == rb + 0x7005 or rb + 0x7012 <= a <= rb + 0x701f: girl += 1
        if girl: res[tab] = (entry, girl, len(calls))
    return res
if __name__ == '__main__':
    for g in sys.argv[1:]:
        d = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'prog_%s.bin' % g), 'rb').read()
        print(g, {hex(k): (hex(v[0]), v[1], v[2]) for k, v in face_tables(d).items()})
