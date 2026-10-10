#!/usr/bin/env python3
"""Proposes lib/PMD_scale.lua: the size each PMDCollab species must be drawn at to look
as big as its HGSS / PokeMMO counterpart does after lib/HGSS_scale.lua.

For every species with both sprites it measures the median visible height of the art
(the same measure tools/generate_pmd_sprites.py's true-size scale uses: HGSS stand and
walk frames, every PMD Walk cell) and the median visible area, and sets

    PMD scale = (HGSS height x HGSS_scale[dex]) / PMD height

Writes nothing unless --out is given (it never touches lib/PMD_scale.lua by itself, which
is hand-tuned). Needs assets/pmd and assets/wilds_generated baked.

    python3 tools/generate_pmd_scale.py                       # summary + outliers
    python3 tools/generate_pmd_scale.py --out proposed.lua    # also write the table
    python3 tools/generate_pmd_scale.py --min 0.45 --max 1.25 --metric blend
"""
from __future__ import annotations

import argparse
import json
import re
import statistics
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent


def lua_table(path: Path) -> dict[int, tuple[float, str]]:
    out = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"\s*\[(\d+)\] = ([\d.]+),\s*(?:--\s*(.*))?$", line)
        if m:
            out[int(m.group(1))] = (float(m.group(2)), (m.group(3) or "").strip())
    return out


def medians(sheet: Image.Image, cells, cw: int, ch: int):
    hs, ar = [], []
    for x, y in cells:
        box = sheet.crop((x, y, x + cw, y + ch)).getchannel("A").getbbox()
        if box:
            hs.append(box[3] - box[1])
            ar.append((box[2] - box[0]) * (box[3] - box[1]))
    return (statistics.median(hs), statistics.median(ar)) if hs else (None, None)


def measure(dex: int, entry: dict):
    hp = ROOT / f"assets/wilds_generated/true_size18/hgss/{dex:03d}-normal.png"
    pp = ROOT / f"assets/pmd/walk/{dex:03d}-normal.png"
    if not (hp.is_file() and pp.is_file()):
        return None
    h = Image.open(hp).convert("RGBA")
    fh = h.height // 18
    hh, ha = medians(h, [(0, i * fh) for i in range(9)], h.width, fh)
    w = entry["walk"]
    p = Image.open(pp).convert("RGBA")
    ph, pa = medians(p, [(c * w["cw"], r * w["ch"]) for r in range(4) for c in range(w["cols"])], w["cw"], w["ch"])
    if not (hh and ph):
        return None
    return hh, ha, ph, pa


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", help="write the proposed table here (e.g. proposed.lua)")
    ap.add_argument("--min", type=float, default=0.4, help="smallest size to propose (default 0.4)")
    ap.add_argument("--max", type=float, default=1.3, help="largest size to propose (default 1.3)")
    ap.add_argument("--metric", choices=("height", "area", "blend"), default="height",
                    help="match height (default), area (sqrt of it), or the mean of both")
    ap.add_argument("--floor", nargs=4, type=float, metavar=("SMALL_SCALE", "BIG_SCALE", "SMALL_PX", "BIG_PX"),
                    help="a pixel-density floor by size: a species whose tuned HGSS height is SMALL_PX or less is "
                         "never drawn below SMALL_SCALE, one of BIG_PX or more never below BIG_SCALE, linear "
                         "between (e.g. --floor 0.49 0.8 12 27). Keeps big Pokemon from being shrunk to a tiny, "
                         "too-fine sprite while small ones stay small.")
    ap.add_argument("--flag", type=float, default=0.15, help="report species where height and area disagree by more than this")
    args = ap.parse_args()

    hgss = lua_table(ROOT / "lib/HGSS_scale.lua")
    index = json.loads((ROOT / "assets/pmd/index.json").read_text(encoding="utf-8"))["dex"]
    rows = []
    for key, entry in index.items():
        if not key.isdigit():
            continue
        dex = int(key)
        m = measure(dex, entry)
        if not m:
            continue
        hh, ha, ph, pa = m
        factor = hgss.get(dex, (1.0, ""))[0]
        by_h = hh * factor / ph
        by_a = (ha ** 0.5) * factor / (pa ** 0.5)
        want = {"height": by_h, "area": by_a, "blend": (by_h + by_a) / 2}[args.metric]
        if args.floor:
            lo_s, hi_s, lo_px, hi_px = args.floor
            t = max(0.0, min(1.0, (hh * factor - lo_px) / (hi_px - lo_px)))
            want = max(want, lo_s + (hi_s - lo_s) * t)
        rows.append((dex, hgss.get(dex, (1, ""))[1] or f"#{dex}", by_h, by_a, max(args.min, min(args.max, want)), want))

    if not rows:
        print("no species with both an HGSS and a PMD sheet (bake them first)", file=sys.stderr)
        return 1
    wants = sorted(r[5] for r in rows)
    pct = lambda p: wants[int(p * (len(wants) - 1))]
    print(f"{len(rows)} species compared, metric = {args.metric}" + (f", floor {args.floor}" if args.floor else ""))
    print(f"scale needed: min {wants[0]:.2f}  p10 {pct(.1):.2f}  median {statistics.median(wants):.2f}  "
          f"p90 {pct(.9):.2f}  max {wants[-1]:.2f}")
    clamped = [r for r in rows if abs(r[4] - r[5]) > 1e-9]
    print(f"clamped to [{args.min}, {args.max}]: {len(clamped)} species")
    split = sorted((r for r in rows if abs(r[2] - r[3]) / max(r[2], r[3]) > args.flag),
                   key=lambda r: -abs(r[2] - r[3]))
    print(f"height and area disagree by more than {args.flag:.0%}: {len(split)} species (check these by eye):")
    for r in split[:25]:
        print(f"  {r[0]:4} {r[1]:<14} by height x{r[2]:.2f}   by area x{r[3]:.2f}")
    if args.out:
        lines = [
            "-- Per-species overworld display size for the PMDCollab sheets (national dex -> scale,",
            "-- 1.0 = the sprite's own size). Proposed by tools/generate_pmd_scale.py: each species",
            "-- is sized so its art is as big as its HGSS sprite is after lib/HGSS_scale.lua.",
            "-- Hand-tune any value; lib/hd_field.lua applies it (with the gen3-hd-sprites library,",
            "-- Species Sizes on) about the sprite's ground point, multiplied by Overworld Size.",
            "-- A form is sized like its base species; a form key (\"479-heat\") sizes one form.",
            "return {",
        ]
        for dex, name, _bh, _ba, size, _w in sorted(rows):
            lines.append(f"  [{dex}] = {size:.2f}, -- {name}")
        lines.append("}")
        Path(args.out).write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
        print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
