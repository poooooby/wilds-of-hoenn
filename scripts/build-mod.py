#!/usr/bin/env python3
"""Builds the release ZIP for wilds_of_hoenn.

Packs manifest.json, main.lua, options.lua, lib/, assets/ and
THIRD_PARTY_NOTICES.md at the ZIP root (manifest.json at the root, not in
a wrapping folder -- required for a clean Mod Manager import). Excludes
tests/, tools/, scripts/, docs/, .git*, and any dev-only file.

Usage:
  python3 scripts/build-mod.py
"""
from __future__ import annotations

import json
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"

INCLUDE_ROOTS = ["manifest.json", "main.lua", "options.lua", "lib", "assets"]
OPTIONAL_FILES = ["THIRD_PARTY_NOTICES.md", "README.md", "CHANGELOG.md"]

# Never ship, even if present under an included root (defense in depth --
# mirrors Wilds of Kanto Revival's FORBIDDEN_NAMES check).
FORBIDDEN_SUFFIXES = (".pyc", ".pyo")
FORBIDDEN_NAMES = {"wilds_dev.flag", ".DS_Store", "Thumbs.db"}


def iter_files():
    for root_name in INCLUDE_ROOTS:
        root = ROOT / root_name
        if root.is_file():
            yield root, root.relative_to(ROOT)
        elif root.is_dir():
            for p in sorted(root.rglob("*")):
                if p.is_file():
                    yield p, p.relative_to(ROOT)
    for name in OPTIONAL_FILES:
        p = ROOT / name
        if p.is_file():
            yield p, p.relative_to(ROOT)


def main() -> int:
    manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
    version = manifest["version"]
    mod_id = manifest["id"]

    DIST.mkdir(exist_ok=True)
    zip_path = DIST / f"wilds-of-hoenn-v{version}.zip"

    forbidden_hits = []
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        seen = set()
        for abs_path, rel_path in iter_files():
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

    print(f"wrote {zip_path}  ({len(names)} files, mod id {mod_id})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
