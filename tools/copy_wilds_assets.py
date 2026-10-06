#!/usr/bin/env python3
"""Copy Wilds of Kanto Revival's overworld sprite sheets into this repo.

Source of truth stays the sibling `overworld-spawn-mod` checkout. This mod
never edits that art; it only takes a read-only copy at build/dev time so
the two repos can diverge (Wilds keeps updating its art independently).

Poke Followers / GSC (16x16 Classic), dex 1-386:
    dex 1-251   -> assets/enhanced_overworld/poke_followers/   (primary)
    dex 252-386 -> assets/enhanced_overworld/Pokewilds/        (extension,
                   falls through for any dex missing in the primary set)

HGSS / PokeMMO (variable per-species native size -- "True Size"), dex 1-386:
    assets/wilds_generated/true_size/hgss/%03d-normal.png / -shiny.png

Usage:
    python3 tools/copy_wilds_assets.py [--source ../overworld-spawn-mod] [--max-dex 386]
"""
import argparse
import pathlib
import shutil
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent

FOLLOWER_FOLDERS = ("poke_followers", "Pokewilds")


def copy_followers(source_root, dest_root, max_dex):
    copied, skipped_over_cap = 0, 0
    for folder in FOLLOWER_FOLDERS:
        src_dir = source_root / "assets" / "enhanced_overworld" / folder
        if not src_dir.is_dir():
            print(f"warn: missing source folder {src_dir}", file=sys.stderr)
            continue
        dst_dir = dest_root / "assets" / "enhanced_overworld" / folder
        dst_dir.mkdir(parents=True, exist_ok=True)
        for src_file in sorted(src_dir.glob("follower_*_*.png")):
            name = src_file.stem  # follower_001_normal
            parts = name.split("_")
            if len(parts) < 3:
                continue
            dex_str = parts[1]
            if not dex_str.isdigit():
                # Form variants like follower_351-01_normal are post-386
                # Gen3 species forms; skip for this mod's v1 (base species only).
                continue
            dex = int(dex_str)
            if dex > max_dex:
                skipped_over_cap += 1
                continue
            shutil.copy2(src_file, dst_dir / src_file.name)
            copied += 1
    return copied, skipped_over_cap


def copy_hgss(source_root, dest_root, max_dex):
    src_dir = source_root / "assets" / "wilds_generated" / "true_size" / "hgss"
    if not src_dir.is_dir():
        print(f"warn: missing source folder {src_dir}", file=sys.stderr)
        return 0, 0
    dst_dir = dest_root / "assets" / "wilds_generated" / "true_size" / "hgss"
    dst_dir.mkdir(parents=True, exist_ok=True)
    copied, skipped_over_cap = 0, 0
    for src_file in sorted(src_dir.glob("*-*.png")):
        name = src_file.stem  # 001-normal
        dex_str = name.split("-", 1)[0]
        if not dex_str.isdigit():
            continue
        dex = int(dex_str)
        if dex > max_dex:
            skipped_over_cap += 1
            continue
        shutil.copy2(src_file, dst_dir / src_file.name)
        copied += 1
    return copied, skipped_over_cap


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", default=str(REPO_ROOT.parent / "overworld-spawn-mod"),
                     help="path to the overworld-spawn-mod (Wilds of Kanto Revival) checkout")
    ap.add_argument("--max-dex", type=int, default=386,
                     help="highest national dex number to copy (Gen 3 cap)")
    args = ap.parse_args()

    source_root = pathlib.Path(args.source)
    if not source_root.is_dir():
        print(f"source not found: {source_root}", file=sys.stderr)
        return 1

    f_copied, f_skipped = copy_followers(source_root, REPO_ROOT, args.max_dex)
    print(f"Poke Followers / GSC: copied {f_copied} files"
          + (f" (skipped {f_skipped} beyond dex {args.max_dex})" if f_skipped else ""))

    h_copied, h_skipped = copy_hgss(source_root, REPO_ROOT, args.max_dex)
    print(f"HGSS / PokeMMO:       copied {h_copied} files"
          + (f" (skipped {h_skipped} beyond dex {args.max_dex})" if h_skipped else ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
