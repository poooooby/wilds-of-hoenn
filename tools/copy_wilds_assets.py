#!/usr/bin/env python3
"""Copy the Wilds of Kanto Revival overworld walker sheets into this repo.

Source of truth stays the sibling `overworld-spawn-mod` checkout. This mod
never edits that art; it only takes a read-only copy at build/dev time so
the two repos can diverge (Wilds keeps updating its art independently).

dex 1-251   -> assets/enhanced_overworld/poke_followers/   (primary)
dex 252-386 -> assets/enhanced_overworld/Pokewilds/        (extension, falls
                                                             through for any
                                                             dex missing in
                                                             the primary set)

Usage:
    python3 tools/copy_wilds_assets.py [--source ../overworld-spawn-mod] [--max-dex 386]
"""
import argparse
import pathlib
import shutil
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
DEST_ROOT = REPO_ROOT / "assets" / "enhanced_overworld"

FOLDERS = ("poke_followers", "Pokewilds")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", default=str(REPO_ROOT.parent / "overworld-spawn-mod"),
                     help="path to the overworld-spawn-mod (Wilds of Kanto Revival) checkout")
    ap.add_argument("--max-dex", type=int, default=386,
                     help="highest national dex number to copy (Gen 3 cap)")
    args = ap.parse_args()

    source_root = pathlib.Path(args.source) / "assets" / "enhanced_overworld"
    if not source_root.is_dir():
        print(f"source not found: {source_root}", file=sys.stderr)
        return 1

    copied = 0
    skipped_over_cap = 0
    for folder in FOLDERS:
        src_dir = source_root / folder
        if not src_dir.is_dir():
            print(f"warn: missing source folder {src_dir}", file=sys.stderr)
            continue
        dst_dir = DEST_ROOT / folder
        dst_dir.mkdir(parents=True, exist_ok=True)
        for src_file in sorted(src_dir.glob("follower_*_*.png")):
            name = src_file.stem  # follower_001_normal
            parts = name.split("_")
            if len(parts) < 3:
                continue
            dex_str = parts[1]
            if not dex_str.isdigit():
                # Form variants like follower_351-01_normal are post-386 Gen3
                # species forms; skip for this mod's v1 (base species only).
                continue
            dex = int(dex_str)
            if dex > args.max_dex:
                skipped_over_cap += 1
                continue
            dst_file = dst_dir / src_file.name
            shutil.copy2(src_file, dst_file)
            copied += 1

    print(f"copied {copied} files into {DEST_ROOT}")
    if skipped_over_cap:
        print(f"skipped {skipped_over_cap} files beyond dex {args.max_dex}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
