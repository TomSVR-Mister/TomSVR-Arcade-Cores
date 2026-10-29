"""Quantify diagnostic ISR and video phase sweeps, including the preceding row."""
import json
import re
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent / "hud_runs"
PHASES = (0, -16, -24, -32, -40, -48, -64, -80, -104)
LATENCIES = (12, 24, 36, 48)


def pixels(path):
    return np.asarray(Image.open(path))


def differences(a, b):
    yy, xx = np.where(np.any(a != b, axis=2))
    return {
        "count": int(len(xx)),
        "rows": {
            str(y): {"count": int(np.sum(yy == y)),
                     "xmin": int(xx[yy == y].min()),
                     "xmax": int(xx[yy == y].max())}
            for y in np.unique(yy)
        },
    }


def main():
    text = (ROOT / "timing/irq_phase_sweep.log").read_text()
    expected = [("f3", "03"), ("f2", "10"), ("f0", "00"), ("f1", "00"), ("f8", "ef")]
    for phase in range(32):
        writes = re.findall(rf"WRITE phase={phase} port=(\w+) data=(\w+)", text)
        assert writes == expected, (phase, writes)
    irq = {}
    for port in ("f3", "f2", "f0", "f1", "f8"):
        rows = re.findall(rf"WRITE phase=(\d+) port={port} .*?tstates=([\d.]+) pixels=([\d.]+)", text)
        irq[port] = {"runs": len(rows),
                     "min_tstates": min(float(r[1]) for r in rows),
                     "max_tstates": max(float(r[1]) for r in rows),
                     "min_pixels": min(float(r[2]) for r in rows),
                     "max_pixels": max(float(r[2]) for r in rows)}
        assert len(rows) == 32, (port, len(rows))
    results = {"irq": irq, "video": {}}
    for title in ("brutforc", "pigout"):
        folder = ROOT / title
        reference = pixels(folder / "replay_mode3_phase0_lat12.ppm")
        runs = []
        for latency in LATENCIES:
            for phase in PHASES:
                modes = {mode: pixels(folder / f"replay_mode{mode}_phase{phase}_lat{latency}.ppm")
                         for mode in (0, 3, 4)}
                runs.append({"phase": phase, "latency": latency,
                             "actual_vs_reference": differences(modes[0], reference),
                             "ideal_live_vs_reference": differences(modes[4], reference),
                             "ideal_scanline_vs_reference": differences(modes[3], reference),
                             "actual_vs_ideal_live": differences(modes[0], modes[4])})
        results["video"][title] = runs
        if title == "brutforc":
            for run in runs:
                if run["phase"] in (-40, -48, -64, -80):
                    assert run["actual_vs_reference"]["count"] == 0, run
                if run["phase"] == -104:
                    assert "207" in run["actual_vs_reference"]["rows"], run
        else:
            assert all(run["actual_vs_reference"]["count"] == 0
                       for run in runs if run["latency"] == 12)
        print(title, "phase", "latency", "actual", "ideal_live", "ideal_scanline", "rows")
        for run in runs:
            print(run["phase"], run["latency"], run["actual_vs_reference"]["count"],
                  run["ideal_live_vs_reference"]["count"], run["ideal_scanline_vs_reference"]["count"],
                  run["actual_vs_reference"]["rows"])
    (ROOT / "timing/phase_metrics.json").write_text(json.dumps(results, indent=2) + "\n")
    print("ISR", irq)

    # Inspect the entire transition, so advancing writes cannot hide a new defect
    # on the preceding world row.
    rows = [("Recorded phase, FIFO fix", 0, 0),
            ("Recorded phase, ideal live tile supply", 4, 0),
            ("Writes 40 pixels earlier, FIFO fix", 0, -40),
            ("Writes 64 pixels earlier, FIFO fix", 0, -64),
            ("Writes 104 pixels earlier, FIFO fix", 0, -104),
            ("Scanline-selected reference", 3, 0)]
    out = Image.new("RGB", (1280, len(rows) * 125), "#202020")
    draw = ImageDraw.Draw(out)
    for i, (label, mode, phase) in enumerate(rows):
        src = Image.open(ROOT / "brutforc" / f"replay_mode{mode}_phase{phase}_lat12.ppm")
        strip = src.crop((0, 200, 320, 224)).resize((1280, 96), Image.Resampling.NEAREST)
        draw.text((8, i * 125 + 5), label, fill="white")
        out.paste(strip, (0, i * 125 + 27))
    out.save(ROOT / "timing/brutforc_phase_comparison.png")


if __name__ == "__main__":
    main()
