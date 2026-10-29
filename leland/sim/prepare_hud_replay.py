"""Extract the raw graphics/PROM sections from locally generated MRA images."""
from pathlib import Path

base = Path(__file__).parent
for game, size in [('brutforc',0x180000),('pigout',0x18000)]:
    data = (base / f'{game}_image.bin').read_bytes()
    out = base / 'hud_runs' / game
    out.mkdir(parents=True, exist_ok=True)
    (out / 'gfx.bin').write_bytes(data[0x400010:0x400010+size])
    if game == 'pigout':
        (out / 'prom.bin').write_bytes(data[0x600010:0x620010])
