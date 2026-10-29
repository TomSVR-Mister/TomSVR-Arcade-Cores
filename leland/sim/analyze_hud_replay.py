"""Summarize replay differences and save a figure showing the original HUD lines."""
from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageDraw, ImageFont

base = Path(__file__).parent / 'hud_runs'
summary = {}
panels = []
for game, row in [('pigout', 217), ('brutforc', 208)]:
    results = {}
    for phase in [-16, 0, 16]:
        original = np.array(Image.open(base / game / f'replay_mode0_phase{phase}.ppm'))
        corrected = np.array(Image.open(base / game / f'replay_mode3_phase{phase}.ppm'))
        diff = np.any(original != corrected, axis=2)
        changed = []
        for y in np.flatnonzero(diff.any(axis=1)):
            xs = np.flatnonzero(diff[y])
            changed.append({'y': int(y), 'x_first': int(xs[0]), 'x_last': int(xs[-1]), 'pixels': int(len(xs))})
        results[str(phase)] = changed
        if phase == 0:
            for label, data in [('Original RTL', original), ('Queue data replaced in testbench', corrected)]:
                img = Image.fromarray(data)
                img.save(base / game / f'{"original" if label.startswith("Original") else "counterfactual"}.png')
                panels.append((f'{game} | {label} | native scanline {row}', img.crop((0, row-5, 120, row+15)).resize((960,160),Image.Resampling.NEAREST)))
    original=np.array(Image.open(base/game/'replay_mode0_phase0.ppm'))
    live=np.array(Image.open(base/game/'replay_mode4_phase0.ppm'))
    ideal=np.array(Image.open(base/game/'replay_mode3_phase0.ppm'))
    for label,left,right in [('queue_only',original,live),('live_timing',live,ideal)]:
        diff=np.any(left!=right,axis=2)
        results[label]=[{'y':int(y),'x_first':int(np.flatnonzero(diff[y])[0]),'x_last':int(np.flatnonzero(diff[y])[-1]),'pixels':int(diff[y].sum())} for y in np.flatnonzero(diff.any(axis=1))]
    summary[game] = results
print(json.dumps(summary, indent=2))
(base / 'replay_metrics.json').write_text(json.dumps(summary, indent=2)+'\n')
canvas = Image.new('RGB',(1000,850),'#17202c')
draw = ImageDraw.Draw(canvas)
font = ImageFont.load_default(size=20)
for i,(label,img) in enumerate(panels):
    y = 15 + i*208
    draw.text((20,y),label,font=font,fill='white')
    canvas.paste(img,(20,y+30))
canvas.save(base / 'hud_comparison.png')
