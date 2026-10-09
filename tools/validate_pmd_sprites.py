#!/usr/bin/env python3
"""Check a tools/generate_pmd_sprites.py bake: every species in
assets/pmd/index.json has its Walk and Idle sheets, each sheet is exactly
cols x 4 directions of cw x ch cells, durations match the frame count, the
ground anchor lies near its cell, a species flagged `shiny` has the shiny
sheet, and no stray sheet exists without an index entry.

    python3 tools/validate_pmd_sprites.py            # validates assets/pmd/

Exit code 0 = OK. Skips cleanly (exit 0) when the bake does not exist, so a
checkout without SpriteCollab can still run scripts/build-mod.py.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
PMD = ROOT / "assets" / "pmd"
ANIMS = ("walk", "idle")
OPTIONAL_ANIMS = ("attack", "hurt")  # present for most species, never required
DIRECTIONS = 4


def sheet_name(key: str) -> str:
    """"25" -> "025"; a form key "479-heat" -> "479-heat" (already padded)."""
    base, _, form = key.partition("-")
    return f"{int(base):03d}" + (f"-{form}" if form else "")


def main() -> int:
    index_path = PMD / "index.json"
    if not index_path.is_file():
        print("validate_pmd_sprites: no assets/pmd/index.json -- skipped (PMDCollab style not baked)")
        return 0
    index = json.loads(index_path.read_text(encoding="utf-8"))
    errors: list[str] = []
    if index.get("version") != 1:
        errors.append(f"unsupported index version {index.get('version')!r}")
    dex_map = index.get("dex", {})
    expected: set[str] = set()

    for dex, entry in sorted(dex_map.items(), key=lambda kv: (int(kv[0].split("-")[0]), kv[0])):
        for anim in ANIMS + OPTIONAL_ANIMS:
            e = entry.get(anim)
            if not isinstance(e, dict):
                if anim in ANIMS:
                    errors.append(f"{dex}: no {anim} entry")
                continue
            cw, ch, cols = e.get("cw"), e.get("ch"), e.get("cols")
            if not all(isinstance(v, int) and v > 0 for v in (cw, ch, cols)):
                errors.append(f"{dex} {anim}: bad cell size/cols {cw}x{ch} cols={cols}")
                continue
            if len(e.get("durations", [])) != cols or any(d <= 0 for d in e["durations"]):
                errors.append(f"{dex} {anim}: durations {e.get('durations')} do not match {cols} frames")
            if not (-cw <= e.get("ax", -1e9) <= 2 * cw and -ch <= e.get("ay", -1e9) <= 2 * ch):
                errors.append(f"{dex} {anim}: ground anchor ({e.get('ax')},{e.get('ay')}) far outside the {cw}x{ch} cell")
            variants = ["normal"] + (["shiny"] if e.get("shiny") else [])
            for variant in variants:
                rel = f"{anim}/{sheet_name(dex)}-{variant}.png"
                expected.add(rel)
                p = PMD / rel
                if not p.is_file():
                    errors.append(f"{dex}: missing {rel}")
                    continue
                with Image.open(p) as im:
                    if im.size != (cw * cols, ch * DIRECTIONS):
                        errors.append(f"{rel}: size {im.size}, expected {(cw * cols, ch * DIRECTIONS)}")

    for anim in ANIMS + OPTIONAL_ANIMS:
        d = PMD / anim
        if d.is_dir():
            for p in sorted(d.glob("*.png")):
                rel = f"{anim}/{p.name}"
                if rel not in expected:
                    errors.append(f"stray sheet without an index entry: {rel}")

    # portraits
    pidx_path = PMD / "portraits.json"
    portraits = 0
    if pidx_path.is_file():
        pidx = json.loads(pidx_path.read_text(encoding="utf-8"))
        size = pidx.get("size")
        pexpected: set[str] = set()
        for dex, entry in sorted(pidx.get("dex", {}).items(), key=lambda kv: int(kv[0])):
            emotions = entry.get("emotions") or []
            if "Normal" not in emotions:
                errors.append(f"portrait {dex}: no Normal emotion")
            for variant in ["normal"] + (["shiny"] if entry.get("shiny") else []):
                rel = f"portraits/{int(dex):03d}-{variant}.png"
                pexpected.add(rel)
                p = PMD / rel
                if not p.is_file():
                    errors.append(f"portrait {dex}: missing {rel}")
                    continue
                portraits += 1
                with Image.open(p) as im:
                    if im.size != (size * len(emotions), size):
                        errors.append(f"{rel}: size {im.size}, expected {(size * len(emotions), size)}")
        d = PMD / "portraits"
        if d.is_dir():
            for p in sorted(d.glob("*.png")):
                if f"portraits/{p.name}" not in pexpected:
                    errors.append(f"stray portrait sheet without an index entry: portraits/{p.name}")

    if errors:
        print(f"PMD sprite validation FAILED ({len(errors)} problems):")
        for e in errors[:40]:
            print("  -", e)
        return 1
    print(f"PMD sprite validation OK: {len(dex_map)} species, {len(expected)} sheets, {portraits} portrait sheets")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
