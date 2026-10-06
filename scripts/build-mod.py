#!/usr/bin/env python3
"""Builds the release ZIP for wilds_of_hoenn.

Packs manifest.json, main.lua, options.lua, lib/, assets/ and
THIRD_PARTY_NOTICES.md at the ZIP root (manifest.json at the root, not in
a wrapping folder -- required for a clean Mod Manager import). Excludes
tests/, tools/, scripts/, docs/, .git*, and any dev-only file.

Atlas mode (default): bakes the ~3900 individual sprite sheets
(tools/generate_sprite_atlases.py) into a handful of shard PNGs under
assets/atlas/, validates the bake is lossless and complete
(tools/validate_sprite_atlases.py), and ships THOSE instead of the
per-file sheets -- the release ZIP and the git history never carry 3900+
individual PNGs; see lib/sprite_atlas.lua.

Usage:
  python3 scripts/build-mod.py              # atlas mode (default)
  python3 scripts/build-mod.py --no-atlas   # old per-file layout
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"

INCLUDE_ROOTS = ["manifest.json", "main.lua", "options.lua", "lib", "assets"]
OPTIONAL_FILES = ["THIRD_PARTY_NOTICES.md", "README.md", "CHANGELOG.md"]

# Raw per-file sprite sheets -- read-only copies from a sibling
# overworld-spawn-mod checkout (tools/copy_wilds_assets.py), excluded from
# an atlas-mode build since assets/atlas/ ships in their place.
RAW_SPRITE_DIRS = ["assets/enhanced_overworld", "assets/wilds_generated/true_size/hgss"]

# Never ship, even if present under an included root (defense in depth --
# mirrors Wilds of Kanto Revival's FORBIDDEN_NAMES check).
FORBIDDEN_SUFFIXES = (".pyc", ".pyo")
FORBIDDEN_NAMES = {"wilds_dev.flag", ".DS_Store", "Thumbs.db"}


def run_tool(*args: str) -> None:
    result = subprocess.run([sys.executable, *args], cwd=ROOT)
    if result.returncode != 0:
        raise SystemExit(result.returncode)


def iter_files(skip_dirs: set[Path]):
    for root_name in INCLUDE_ROOTS:
        root = ROOT / root_name
        if root.is_file():
            yield root, root.relative_to(ROOT)
        elif root.is_dir():
            for p in sorted(root.rglob("*")):
                if p.is_file() and not any(skip in p.parents or skip == p for skip in skip_dirs):
                    yield p, p.relative_to(ROOT)
    for name in OPTIONAL_FILES:
        p = ROOT / name
        if p.is_file():
            yield p, p.relative_to(ROOT)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--no-atlas", action="store_true", help="ship the raw per-file sheets instead of a baked atlas")
    args = ap.parse_args()

    manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
    version = manifest["version"]
    mod_id = manifest["id"]

    skip_dirs: set[Path] = set()
    if args.no_atlas:
        atlas_dir = ROOT / "assets" / "atlas"
        if atlas_dir.is_dir():
            skip_dirs.add(atlas_dir)
        for d in RAW_SPRITE_DIRS:
            p = ROOT / d
            if not p.is_dir():
                print(f"ERROR: --no-atlas needs the real sheets at {d} "
                      f"(run tools/copy_wilds_assets.py)", file=sys.stderr)
                return 1
    else:
        run_tool("tools/generate_sprite_atlases.py")
        run_tool("tools/validate_sprite_atlases.py")
        for d in RAW_SPRITE_DIRS:
            p = ROOT / d
            if p.is_dir():
                skip_dirs.add(p)
        if not (ROOT / "assets" / "atlas" / "index.json").is_file():
            print("ERROR: atlas build did not produce assets/atlas/index.json", file=sys.stderr)
            return 1

    DIST.mkdir(exist_ok=True)
    zip_path = DIST / f"wilds-of-hoenn-v{version}.zip"

    forbidden_hits = []
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        seen = set()
        for abs_path, rel_path in iter_files(skip_dirs):
            rel_str = rel_path.as_posix()
            if rel_str in seen:
                continue
            seen.add(rel_str)
            if abs_path.name in FORBIDDEN_NAMES or rel_path.suffix in FORBIDDEN_SUFFIXES:
                forbidden_hits.append(rel_str)
                continue
            z.write(abs_path, rel_str)

    if forbidden_hits:
        for hit in forbidden_hits:
            print(f"ERROR: forbidden file would have shipped: {hit}", file=sys.stderr)
        zip_path.unlink(missing_ok=True)
        return 1

    with zipfile.ZipFile(zip_path) as z:
        names = z.namelist()
        if "manifest.json" not in names:
            print("ERROR: manifest.json not at ZIP root", file=sys.stderr)
            return 1
        if not args.no_atlas:
            leaked = [n for n in names if n.startswith("assets/enhanced_overworld/")
                      or n.startswith("assets/wilds_generated/true_size/hgss/")]
            if leaked:
                print(f"ERROR: atlas mode but {len(leaked)} raw sprite files leaked into the ZIP "
                      f"(first: {leaked[0]})", file=sys.stderr)
                zip_path.unlink(missing_ok=True)
                return 1

    mode = "per-file" if args.no_atlas else "atlas"
    print(f"wrote {zip_path}  ({len(names)} files, {mode} mode, mod id {mod_id})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
