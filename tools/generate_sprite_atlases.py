#!/usr/bin/env python3
"""Bake the overworld sprite sheets into shard atlases plus JSON indexes
(a release-ZIP build output, adapted from Wilds of Kanto Revival's
tools/generate_sprite_atlases.py -- same format, same lib/sprite_atlas.lua
index schema, two families instead of ~15).

The game normally asks for one small PNG per sprite (1000+ files across
both Sprite Styles). This tool packs each sprite FAMILY (a set of
directories of `<dex>-<variant>.png` or `follower_<dex>_<variant>.png`
sheets) into a few shard PNGs and writes an index mapping every original
relative path to its rectangle. lib/sprite_atlas.lua serves those paths
from the shards at runtime as a fallback, after the real per-file path --
nothing that asks for e.g.
`assets/wilds_generated/true_size/hgss/025-normal.png` has to change.

    python3 tools/generate_sprite_atlases.py                     # both families
    python3 tools/generate_sprite_atlases.py --families hgss     # just one

Output (default `assets/atlas/`, gitignored, rebuilt by scripts/build-mod.py):
    index.json               { version, families: { <name>: { index, dirs: [...] } } }
    <family>.json            { version, family, shards: [{file,w,h}], dirs: { <dir>: { <name>: [shard,x,y,w,h] } } }
    <family>_<n>.png         shard atlases (RGBA, lossless; shard numbers are 0-based)

Every sprite is copied pixel for pixel (RGBA, transparent pixels keep
their RGB), so slicing it back out gives exactly the source image.
tools/validate_sprite_atlases.py (copied from Wilds verbatim -- fully
generic, no family names hardcoded) proves that for every sprite.

Layout: each shard is ONE COLUMN, the sprites stacked top to bottom
(width = the widest sprite in the shard). PNG compresses row by row with
a 32 KB deflate window, and a row that mixes several sprites breaks both
the per-row filter choice and the window's reach across a sprite's
frames -- see Wilds of Kanto Revival's own tool for the measured 33-67%
size regression a shelf-packed atlas produced there. Shards stay under
32,768 px tall so they are also legal GPU textures if anyone ever
uploads one.
"""
from __future__ import annotations

import argparse
import glob
import json
import re
import shutil
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
GEN = "assets/wilds_generated"

# family -> list of directory globs (repo-relative). Only top-level PNGs
# of each directory are packed.
FAMILIES: dict[str, list[str]] = {
    "poke_followers": ["assets/enhanced_overworld/poke_followers", "assets/enhanced_overworld/Pokewilds"],
    "hgss": [f"{GEN}/true_size/hgss"],
}
INDEX_VERSION = 1
MAX_SHARD_H = 32768  # tallest shard (also the GPU texture limit that is safe everywhere)
DEFAULT_MAX_SHARD_PX = 1_500_000


def natural_key(text: str):
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", text)]


def family_dirs(patterns: list[str]) -> list[str]:
    out: list[str] = []
    for pat in patterns:
        for hit in sorted(glob.glob(str(ROOT / pat))):
            p = Path(hit)
            if p.is_dir():
                out.append(p.relative_to(ROOT).as_posix())
    return sorted(dict.fromkeys(out), key=natural_key)


def collect(dirs: list[str]):
    """[(dir, name, w, h)] in natural order (by dir, then dex/variant name)."""
    items = []
    for d in dirs:
        for f in sorted((ROOT / d).glob("*.png"), key=lambda p: natural_key(p.name)):
            with Image.open(f) as im:
                w, h = im.size
            items.append((d, f.name, w, h))
    return items


def split_shards(items, max_px: int, max_h: int = MAX_SHARD_H):
    """Consecutive runs of sprites (so neighbouring dex ids share a shard),
    each at most `max_h` tall and about `max_px` pixels (shard width is
    its widest sprite)."""
    shards, cur, height, width = [], [], 0, 0
    for it in items:
        w, h = it[2], it[3]
        new_w = max(width, w)
        if cur and (height + h > max_h or new_w * (height + h) > max_px):
            shards.append(cur)
            cur, height, width, new_w = [], 0, 0, w
        cur.append(it)
        height += h
        width = new_w
    if cur:
        shards.append(cur)
    return shards


def pack_shard(group):
    """One column: sprites stacked in order, left aligned. Returns
    (width, height, [(dir, name, x, y, w, h)])."""
    width = max(w for _, _, w, _ in group)
    placed, y = [], 0
    for d, name, w, h in group:
        placed.append((d, name, 0, y, w, h))
        y += h
    return width, y, placed


def build_family(name: str, dirs: list[str], out_dir: Path, max_px: int) -> dict:
    items = collect(dirs)
    if not items:
        return {"name": name, "sprites": 0, "shards": 0, "px": 0, "src_px": 0, "dirs": dirs, "index": None}
    shards = split_shards(items, max_px, MAX_SHARD_H)
    index = {"version": INDEX_VERSION, "family": name, "shards": [], "dirs": {d: {} for d in dirs}}
    atlas_px = 0
    src_px = sum(w * h for _, _, w, h in items)
    for n, group in enumerate(shards):
        width, height, placed = pack_shard(group)
        atlas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        for d, fname, x, y, w, h in placed:
            with Image.open(ROOT / d / fname) as im:
                atlas.paste(im.convert("RGBA"), (x, y))
            index["dirs"][d][fname] = [n, x, y, w, h]
        rel = f"assets/atlas/{name}_{n}.png"
        atlas.save(out_dir / f"{name}_{n}.png", "PNG", optimize=True)
        index["shards"].append({"file": rel, "w": width, "h": height})
        atlas_px += width * height
    (out_dir / f"{name}.json").write_text(json.dumps(index, separators=(",", ":")), encoding="utf-8")
    return {"name": name, "sprites": len(items), "shards": len(shards), "px": atlas_px, "src_px": src_px,
            "dirs": dirs, "index": f"assets/atlas/{name}.json"}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--families", default=",".join(FAMILIES),
                    help="comma list of family names (default: %(default)s)")
    ap.add_argument("--out", default="assets/atlas", help="output directory, repo-relative (default: %(default)s)")
    ap.add_argument("--max-shard-px", type=int, default=DEFAULT_MAX_SHARD_PX, help="approximate pixels per shard")
    args = ap.parse_args()

    names = [n.strip() for n in args.families.split(",") if n.strip()]
    unknown = [n for n in names if n not in FAMILIES]
    if unknown:
        print(f"unknown families: {unknown}; known: {sorted(FAMILIES)}", file=sys.stderr)
        return 2

    out_dir = ROOT / args.out
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)

    reports = []
    for name in names:
        dirs = family_dirs(FAMILIES[name])
        rep = build_family(name, dirs, out_dir, args.max_shard_px)
        reports.append(rep)
        fill = (rep["src_px"] / rep["px"] * 100) if rep["px"] else 0
        print(f"{name:<14} {rep['sprites']:>5} sprites -> {rep['shards']:>2} shards, "
              f"{rep['px'] / 1e6:5.2f} Mpx atlas ({fill:4.1f}% fill)")

    families = {}
    for r in reports:
        if not r["index"]:
            continue
        families[r["name"]] = {"index": r["index"], "dirs": r["dirs"]}
    root_index = {"version": INDEX_VERSION, "families": families}
    (out_dir / "index.json").write_text(json.dumps(root_index, separators=(",", ":")), encoding="utf-8")
    total_files = len(list(out_dir.iterdir()))
    total_bytes = sum(f.stat().st_size for f in out_dir.iterdir())
    print(f"wrote {out_dir.relative_to(ROOT).as_posix()}/ ({total_files} files, {total_bytes / 1e6:.1f} MB) "
          f"covering {sum(r['sprites'] for r in reports)} sprites")
    return 0


if __name__ == "__main__":
    sys.exit(main())
