#!/usr/bin/env python3
"""Seed lib/pmd_water.lua: the species the PMDCollab style draws WHOLE over water.

Every other PMD Pokemon on water is drawn swimming -- cut off at the baked
waterline with a foam line (tools/generate_pmd_sprites.py, lib/pmd_renderer.lua).
Only true flyers / floaters stay whole. The HGSS levitates pack is not enough on
its own: it also covers species whose PMD art plainly walks (Charizard, Pidgeot,
Dragonite ...), which must sit in the water. So a species is seeded as a flyer when

  * it is in the HGSS levitates pack (assets/wilds_generated/true_size18/levitates), AND
  * its PMD Walk art hovers: the median gap between the baked ground point `ay` and
    the bottom of the body is at least HOVER_PX,

plus EXTRA_FLYERS (clear floaters whose art dangles down to the ground point, so the
gap misses them) and minus NOT_FLYERS (walkers the gap would wrongly keep).

The output is meant to be EDITED BY HAND afterwards, like lib/HGSS_scale.lua and
lib/PMD_scale.lua: re-running this tool overwrites those edits (it asks for --force
when the file exists). The build never runs it.

    python3 tools/generate_pmd_water.py --report     # print the list, write nothing
    python3 tools/generate_pmd_water.py --force
"""
from __future__ import annotations

import argparse
import json
import statistics
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
PMD = ROOT / "assets" / "pmd"
LEVITATES = ROOT / "assets" / "wilds_generated" / "true_size18" / "levitates"
OUT = ROOT / "lib" / "pmd_water.lua"
TRACKER = ROOT.parent / "SpriteCollab" / "tracker.json"
HOVER_PX = 2
DIRECTIONS = 4

EXTRA_FLYERS = {
    92, 93,            # Gastly, Haunter
    200, 429,          # Misdreavus, Mismagius
    251,               # Celebi
    355,               # Duskull
    380, 381, 384,     # Latias, Latios, Rayquaza
    478,               # Froslass
    480, 481, 482,     # Uxie, Mesprit, Azelf
    488,               # Cresselia
    608, 609,          # Lampent, Chandelure
}
NOT_FLYERS = {6, 18, 149, 373}  # Charizard, Pidgeot, Dragonite, Salamence: they walk


def hover_gap(key: str, walk: dict) -> float | None:
    p = PMD / "walk" / f"{key}-normal.png"
    if not p.is_file():
        return None
    sheet = Image.open(p).convert("RGBA")
    cw, ch, cols, ay = walk["cw"], walk["ch"], walk["cols"], walk["ay"]
    gaps = []
    for r in range(DIRECTIONS):
        for c in range(cols):
            box = sheet.crop((c * cw, r * ch, (c + 1) * cw, (r + 1) * ch)).getchannel("A").getbbox()
            if box:
                gaps.append(ay - box[3])
    return statistics.median(gaps) if gaps else None


def names() -> dict[int, str]:
    try:
        t = json.loads(TRACKER.read_text(encoding="utf-8"))
        return {int(k): v.get("name", "").replace("_", " ") for k, v in t.items() if k.isdigit()}
    except (OSError, ValueError):
        return {}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--report", action="store_true", help="print the list, write nothing")
    ap.add_argument("--force", action="store_true", help="overwrite an existing lib/pmd_water.lua")
    args = ap.parse_args()

    index_path = PMD / "index.json"
    if not index_path.is_file() or not LEVITATES.is_dir():
        print("ERROR: needs the PMD bake (tools/generate_pmd_sprites.py) and the HGSS bake "
              "(tools/generate_true_size_18frame.py)", file=sys.stderr)
        return 1
    index = json.loads(index_path.read_text(encoding="utf-8"))["dex"]
    levitates = {int(p.name[:3]) for p in LEVITATES.glob("[0-9][0-9][0-9]-normal.png")}

    fly = set(EXTRA_FLYERS)
    for dex in sorted(levitates):
        entry = index.get(str(dex))
        if not entry:
            continue
        gap = hover_gap(f"{dex:03d}", entry["walk"])
        if gap is not None and gap >= HOVER_PX:
            fly.add(dex)
    fly -= NOT_FLYERS

    nm = names()
    if args.report:
        for dex in sorted(fly):
            print(f"{dex:4d}  {nm.get(dex, '')}")
        print(f"{len(fly)} flyers")
        return 0
    if OUT.exists() and not args.force:
        print(f"ERROR: {OUT.relative_to(ROOT)} exists and may hold hand edits (use --force)", file=sys.stderr)
        return 1
    lines = [
        "-- PMDCollab water: the species drawn WHOLE over water (true flyers and floaters).",
        "-- Every other PMD Pokemon on water swims: cut off at its baked waterline with a",
        "-- foam line (lib/pmd_renderer.lua). EDIT BY HAND: add a species with",
        "-- `[dex] = true`, or a form with `[\"<dex3>-<form>\"] = true` (a form key wins over",
        "-- its dex; `false` keeps a form swimming when its base species flies).",
        "-- Seeded by tools/generate_pmd_water.py (re-running it overwrites edits).",
        "return {",
        "  fly = {",
    ]
    for dex in sorted(fly):
        lines.append(f"    [{dex}] = true, -- {nm.get(dex, '')}".rstrip(" -"))
    lines += ["  },", "}", ""]
    OUT.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"wrote {OUT.relative_to(ROOT)}: {len(fly)} flyers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
