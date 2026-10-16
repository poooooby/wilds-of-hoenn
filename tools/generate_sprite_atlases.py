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
`assets/wilds_generated/true_size18/hgss/025-normal.png` has to change.

    python3 tools/generate_sprite_atlases.py                     # every family
    python3 tools/generate_sprite_atlases.py --families hgss18   # just one

Output (default `assets/atlas/`, gitignored, rebuilt by scripts/build-mod.py):
    index.json               { version, families: { <name>: { index, dirs: [...] } } }
    <family>.json            { version, family, shards: [{file,w,h}], dirs: { <dir>: { <name>: [shard,x,y,w,h] } } }
    <family>_<n>.png         shard atlases (RGBA, lossless; shard numbers are 0-based)

Every sprite is copied pixel for pixel (RGBA, transparent pixels keep
their RGB), so slicing it back out gives exactly the source image.
tools/validate_sprite_atlases.py (copied from Wilds verbatim -- fully
generic, no family names hardcoded) proves that for every sprite.

Colour numbers (default; `--rgba` = the old full-colour shards): a sheet
uses few colours (PMDCollab at most ~150), and its shiny is the same
drawing in other colours. So the normal and shiny sheets of one sprite
(`<key>-normal.png` / `<key>-shiny.png` in one directory, same size) are
stored ONCE as a greyscale image of colour numbers, each number standing
for one (normal colour, shiny colour) pair -- exact, also where a shiny
splits one normal colour in two. Each sheet's colours are one row of
`<family>_pal.png` (RGBA, column = colour number). lib/sprite_atlas.lua
turns the numbers back into the exact sheet when it is first used. A
sprite with more than 256 pairs is tried alone, then kept full colour in
a `rgba` shard. Family index version 2:
    shards: [{file,w,h,mode = "index" | "rgba"}], palette: {file,w,h},
    dirs: { <dir>: { <name>: [shard,x,y,w,h, palette row (index shards only)] } }

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
import os
import re
import shutil
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
GEN = "assets/wilds_generated"

# family -> list of directory globs (repo-relative). Only top-level PNGs
# of each directory are packed.
#
FAMILIES: dict[str, list[str]] = {
    "hgss18": [f"{GEN}/true_size18/hgss"],
    "swimming18": [f"{GEN}/true_size18/swimming"],
    "levitates18": [f"{GEN}/true_size18/levitates"],
    # PMDCollab Walk/Idle sheets (tools/generate_pmd_sprites.py); optional --
    # a checkout without SpriteCollab has neither directory and bakes nothing.
    "pmd_walk": ["assets/pmd/walk"],
    "pmd_idle": ["assets/pmd/idle"],
    # the overworld-fight animations (Attack, Hurt): optional per species
    "pmd_attack": ["assets/pmd/attack"],
    "pmd_hurt": ["assets/pmd/hurt"],
    # a flying Pokemon's wing-beat in the sky (SpriteCollab Hover): optional per species
    "pmd_fly": ["assets/pmd/fly"],
    # a small fish's leap out of the water (SpriteCollab Hop): only the leaping fish
    "pmd_hop": ["assets/pmd/hop"],
    # the Local Scenes' extra animations (Sleep, Dance, Rotate): a few species only
    "pmd_scene": ["assets/pmd/sleep", "assets/pmd/dance", "assets/pmd/rotate"],
    # the foam overlays a swimming Pokemon is drawn with (mostly transparent, tiny)
    "pmd_foam": ["assets/pmd/foamwalk", "assets/pmd/foamidle", "assets/pmd/foamattack", "assets/pmd/foamhurt"],
    "pmd_portraits": ["assets/pmd/portraits"],
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


MAX_COLOURS = 256
PAIR_NAME = re.compile(r"^(.*)-(normal|shiny)\.png$")


def colour_groups(items):
    """Sprites that share one colour-number image: a directory's `<key>-normal`
    and `<key>-shiny` of the same size, else each sprite alone. Returns
    [(dir, [names], w, h)] in the items' order."""
    by_key: dict[tuple, list] = {}
    order = []
    for d, name, w, h in items:
        m = PAIR_NAME.match(name)
        key = (d, m.group(1)) if m else (d, name)
        if key not in by_key:
            by_key[key] = []
            order.append(key)
        by_key[key].append((name, w, h))
    groups = []
    for key in order:
        members = by_key[key]
        if len({(w, h) for _, w, h in members}) == 1:
            groups.append((key[0], [n for n, _, _ in members], members[0][1], members[0][2]))
        else:
            groups.extend((key[0], [n], w, h) for n, w, h in members)
    return groups


def number_group(d: str, names: list[str]):
    """(index bytes, [colour row per member]) or None when it needs > 256 numbers.
    At most two members (a normal + shiny pair; see colour_groups).
    Numbers are given by how often a pair occurs (most common = 0), which keeps the
    greyscale image as compressible as possible."""
    cols = []
    for n in names:
        with Image.open(ROOT / d / n) as im:
            cols.append(np.frombuffer(im.convert("RGBA").tobytes(), dtype="<u4"))
    # one 64-bit key per pixel = its colour in each member (normal low, shiny high); a 1-D
    # unique is far faster than np.unique(axis=0) on rows
    key = cols[0].astype(np.uint64)
    if len(cols) > 1:
        key |= cols[1].astype(np.uint64) << np.uint64(32)
    pairs, inverse, counts = np.unique(key, return_inverse=True, return_counts=True)
    if len(pairs) > MAX_COLOURS:
        return None
    order = np.lexsort((pairs, -counts))  # most common first, ties by colour (deterministic)
    number = np.empty(len(pairs), dtype=np.uint8)
    number[order] = np.arange(len(pairs), dtype=np.uint8)
    data = number[inverse.reshape(-1)].tobytes()
    sorted_pairs = pairs[order]
    rows = [((sorted_pairs >> np.uint64(32 * m)) & np.uint64(0xFFFFFFFF)).astype("<u4").tobytes()
            for m in range(len(names))]
    return data, rows


def _number_group_args(args):
    return number_group(*args)


# Worker processes for the colour numbering. Not one per hardware thread: every core pinned at
# 100% for minutes is the kind of load that has crashed a desktop (twice, a Ryzen 7800X3D, 16
# threads) -- 4 keeps the build quick and the machine usable. --jobs / WOH_BUILD_JOBS override.
def default_jobs() -> int:
    env = os.environ.get("WOH_BUILD_JOBS")
    if env and env.strip().isdigit() and int(env) > 0:
        return int(env)
    return max(1, min(4, (os.cpu_count() or 2) // 2))


JOBS = default_jobs()


def lower_priority() -> None:
    """Runs this process (and, on Windows, every process it starts) at below-normal
    priority, so a build never competes with the rest of the machine. Best effort."""
    try:
        if sys.platform == "win32":
            import ctypes
            BELOW_NORMAL_PRIORITY_CLASS = 0x4000
            k32 = ctypes.windll.kernel32
            k32.SetPriorityClass(k32.GetCurrentProcess(), BELOW_NORMAL_PRIORITY_CLASS)
        else:
            os.nice(10)
    except Exception:
        pass


def build_family_indexed(name: str, dirs: list[str], out_dir: Path, max_px: int) -> dict:
    items = collect(dirs)
    if not items:
        return {"name": name, "sprites": 0, "shards": 0, "px": 0, "src_px": 0, "dirs": dirs, "index": None}
    numbered, full = [], []  # [(dir, names, w, h, data, rows)], [(dir, name, w, h)]
    groups = colour_groups(items)
    # numbering reads every PNG: spread it over JOBS worker processes (results come back in
    # order), each at below-normal priority
    with ProcessPoolExecutor(max_workers=JOBS, initializer=lower_priority) as pool:
        results = list(pool.map(_number_group_args, [(d, names) for d, names, _, _ in groups], chunksize=8))
    for (d, names, w, h), got in zip(groups, results):
        if got is None and len(names) > 1:
            for n in names:  # the pair together needs too many: try each alone
                alone = number_group(d, [n])
                if alone:
                    numbered.append((d, [n], w, h, *alone))
                else:
                    full.append((d, n, w, h))
        elif got is None:
            full.append((d, names[0], w, h))
        else:
            numbered.append((d, names, w, h, *got))

    index = {"version": 2, "family": name, "shards": [], "dirs": {d: {} for d in dirs}}
    palette_rows: list[bytes] = []
    atlas_px = 0
    src_px = sum(w * h for _, _, w, h in items)
    n = 0
    # colour-number shards: one rectangle per group, shared by its members
    for group in split_shards([(g[0], g, g[2], g[3]) for g in numbered], max_px, MAX_SHARD_H):
        width = max(g[2] for _, g, _, _ in group)
        height = sum(g[3] for _, g, _, _ in group)
        shard = Image.new("L", (width, height), 0)
        y = 0
        for item in group:
            d, names, w, h, data, rows = item[1]
            shard.paste(Image.frombytes("L", (w, h), data), (0, y))
            for member, row in zip(names, rows):
                index["dirs"][d][member] = [n, 0, y, w, h, len(palette_rows)]
                palette_rows.append(row)
            y += h
        shard.save(out_dir / f"{name}_{n}.png", "PNG", optimize=True)
        index["shards"].append({"file": f"assets/atlas/{name}_{n}.png", "w": width, "h": height, "mode": "index"})
        atlas_px += width * height
        n += 1
    # full-colour shards for anything that would not number
    for group in split_shards(full, max_px, MAX_SHARD_H):
        width, height, placed = pack_shard(group)
        atlas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        for d, fname, x, y, w, h in placed:
            with Image.open(ROOT / d / fname) as im:
                atlas.paste(im.convert("RGBA"), (x, y))
            index["dirs"][d][fname] = [n, x, y, w, h]
        atlas.save(out_dir / f"{name}_{n}.png", "PNG", optimize=True)
        index["shards"].append({"file": f"assets/atlas/{name}_{n}.png", "w": width, "h": height, "mode": "rgba"})
        atlas_px += width * height
        n += 1
    if palette_rows:
        pw = max(len(r) for r in palette_rows) // 4
        pal = Image.new("RGBA", (pw, len(palette_rows)), (0, 0, 0, 0))
        for r, row in enumerate(palette_rows):
            pal.paste(Image.frombytes("RGBA", (len(row) // 4, 1), row), (0, r))
        pal.save(out_dir / f"{name}_pal.png", "PNG", optimize=True)
        index["palette"] = {"file": f"assets/atlas/{name}_pal.png", "w": pw, "h": len(palette_rows)}
    (out_dir / f"{name}.json").write_text(json.dumps(index, separators=(",", ":")), encoding="utf-8")
    return {"name": name, "sprites": len(items), "shards": n, "px": atlas_px, "src_px": src_px,
            "dirs": dirs, "index": f"assets/atlas/{name}.json", "full": len(full)}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--families", default=",".join(FAMILIES),
                    help="comma list of family names (default: %(default)s)")
    ap.add_argument("--rgba", action="store_true",
                    help="full-colour shards (index version 1) instead of colour numbers")
    ap.add_argument("--out", default="assets/atlas", help="output directory, repo-relative (default: %(default)s)")
    ap.add_argument("--max-shard-px", type=int, default=DEFAULT_MAX_SHARD_PX, help="approximate pixels per shard")
    ap.add_argument("--jobs", type=int, default=None,
                    help="worker processes for the colour numbering (default: $WOH_BUILD_JOBS, else 4)")
    args = ap.parse_args()
    global JOBS
    if args.jobs and args.jobs > 0:
        JOBS = args.jobs
    lower_priority()

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
        build = build_family if args.rgba else build_family_indexed
        rep = build(name, dirs, out_dir, args.max_shard_px)
        reports.append(rep)
        size = sum(f.stat().st_size for f in out_dir.glob(f"{name}_*.png"))
        extra = f", {rep['full']} full colour" if rep.get("full") else ""
        print(f"{name:<14} {rep['sprites']:>5} sprites -> {rep['shards']:>2} shards, "
              f"{size / 1e6:6.2f} MB{extra}")

    families = {}
    for r in reports:
        if not r["index"]:
            continue
        families[r["name"]] = {"index": r["index"], "dirs": r["dirs"]}
    root_index = {"version": INDEX_VERSION, "families": families}
    (out_dir / "index.json").write_text(json.dumps(root_index, separators=(",", ":")), encoding="utf-8")
    total_files = len(list(out_dir.iterdir()))
    total_bytes = sum(f.stat().st_size for f in out_dir.iterdir())
    shown = out_dir.relative_to(ROOT).as_posix() if out_dir.is_relative_to(ROOT) else out_dir.as_posix()
    print(f"wrote {shown}/ ({total_files} files, {total_bytes / 1e6:.1f} MB) "
          f"covering {sum(r['sprites'] for r in reports)} sprites")
    return 0


if __name__ == "__main__":
    sys.exit(main())
