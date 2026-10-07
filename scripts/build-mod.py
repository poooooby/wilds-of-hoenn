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

Two release variants (both by default):
  hgss      HGSS / PokeMMO art only      -> wilds-of-hoenn-v<ver>-hgss.zip
  pmd       HGSS / PokeMMO + PMDCollab   -> wilds-of-hoenn-v<ver>-hgss-pmd.zip
Same mod id and version, same code -- they differ only in the art they carry
(the mod hides the PMDCollab Sprite Style when no PMD art is installed, see
Config.hasPmdArt). A player installs ONE of them. PMDCollab art is CC BY-NC,
so only the -pmd build is non-commercial-only.

Usage:
  python3 scripts/build-mod.py                      # both variants, atlas mode
  python3 scripts/build-mod.py --variant hgss       # just the HGSS-only ZIP
  python3 scripts/build-mod.py --variant pmd        # just the HGSS + PMDCollab ZIP
  python3 scripts/build-mod.py --no-atlas           # old per-file layout
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"

INCLUDE_ROOTS = ["manifest.json", "main.lua", "options.lua", "lib", "assets"]
OPTIONAL_FILES = ["LICENSE", "THIRD_PARTY_NOTICES.md", "README.md", "CHANGELOG.md"]

# Raw per-file sprite sheets -- read-only copies from a sibling
# overworld-spawn-mod checkout (tools/copy_wilds_assets.py), excluded from
# an atlas-mode build since assets/atlas/ ships in their place.
# `assets/enhanced_overworld` covers the raw
# 4x4-grid source grids (followsprites/, water_sprites/) as one subtree;
# the baked 18-frame output lives separately under wilds_generated.
RAW_SPRITE_DIRS = [
    "assets/enhanced_overworld",
    "assets/wilds_generated/true_size18/hgss",
    "assets/wilds_generated/true_size18/swimming",
    "assets/wilds_generated/true_size18/levitates",
]

# PMDCollab sheets (tools/generate_pmd_sprites.py): OPTIONAL -- a checkout
# without SpriteCollab simply has no PMDCollab style. Same treatment as
# RAW_SPRITE_DIRS in atlas mode (packed into assets/atlas/, per-file copies
# left out), but never required. assets/pmd/index.json, portraits.json and
# CREDITS.txt always ship as they are.
OPTIONAL_RAW_SPRITE_DIRS = [
    "assets/pmd/walk",
    "assets/pmd/idle",
    "assets/pmd/attack",
    "assets/pmd/hurt",
    "assets/pmd/portraits",
]

# Never ship, even if present under an included root (defense in depth --
# mirrors Wilds of Kanto Revival's FORBIDDEN_NAMES check).
FORBIDDEN_SUFFIXES = (".pyc", ".pyo")
FORBIDDEN_NAMES = {"wilds_dev.flag", ".DS_Store", "Thumbs.db"}


def find_spritecollab() -> Path | None:
    """A local SpriteCollab checkout: $SPRITECOLLAB, else a sibling ../SpriteCollab."""
    for cand in (os.environ.get("SPRITECOLLAB"), str(ROOT.parent / "SpriteCollab")):
        if cand and (Path(cand) / "sprite").is_dir() and (Path(cand) / "portrait").is_dir():
            return Path(cand)
    return None


def bake_pmd(rebake: bool) -> bool:
    """Bakes the PMDCollab Walk/Idle sheets + portraits (tools/generate_pmd_sprites.py)
    from a local SpriteCollab checkout. Only sheets that do not exist yet are
    written unless `rebake`, so a normal build is quick. Returns True when
    assets/pmd/ is usable afterwards (baked now, or left over from an earlier
    bake); a checkout without SpriteCollab simply has no PMDCollab style."""
    src = find_spritecollab()
    if src is None:
        have = (ROOT / "assets" / "pmd" / "index.json").is_file()
        print("PMDCollab: no SpriteCollab checkout (set $SPRITECOLLAB or put it at "
              f"{ROOT.parent / 'SpriteCollab'}); "
              + ("using the existing assets/pmd bake" if have else "the PMDCollab style will not be in this build"))
        return have
    print(f"PMDCollab: baking from {src}")
    args = ["tools/generate_pmd_sprites.py", "--src", str(src)]
    if rebake:
        args.append("--force")
    run_tool(*args)
    return True


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


# The atlas families that are HGSS / PokeMMO art (everything not pmd_*).
HGSS_FAMILIES = "hgss18,swimming18,levitates18"
PMD_FAMILIES = ("pmd_walk", "pmd_idle", "pmd_portraits")

VARIANTS = {
    "hgss": {"suffix": "-hgss", "pmd": False, "label": "HGSS / PokeMMO only"},
    "pmd": {"suffix": "-hgss-pmd", "pmd": True, "label": "HGSS / PokeMMO + PMDCollab"},
}


def build_variant(name: str, args, version: str, mod_id: str, out_dir: Path) -> Path | None:
    """Builds one release ZIP. Returns its path, or None after printing why not."""
    spec = VARIANTS[name]
    with_pmd = spec["pmd"]
    print(f"==> variant {name}: {spec['label']}")
    if with_pmd and not (ROOT / "assets" / "pmd" / "index.json").is_file():
        print("ERROR: the PMDCollab variant needs a PMD bake (assets/pmd/index.json): "
              "put SpriteCollab at ../SpriteCollab or set $SPRITECOLLAB", file=sys.stderr)
        return None

    skip_dirs: set[Path] = set()
    if not with_pmd and (ROOT / "assets" / "pmd").is_dir():
        skip_dirs.add(ROOT / "assets" / "pmd")  # an HGSS-only release carries none of it

    if args.no_atlas:
        atlas_dir = ROOT / "assets" / "atlas"
        if atlas_dir.is_dir():
            skip_dirs.add(atlas_dir)
        for d in RAW_SPRITE_DIRS:
            p = ROOT / d
            if not p.is_dir():
                print(f"ERROR: --no-atlas needs the real sheets at {d} "
                      f"(run tools/copy_wilds_assets.py)", file=sys.stderr)
                return None
    else:
        gen = ["tools/generate_sprite_atlases.py"]
        if not with_pmd:
            gen += ["--families", HGSS_FAMILIES]  # the output directory is rebuilt from scratch
        run_tool(*gen)
        run_tool("tools/validate_sprite_atlases.py")
        if with_pmd:
            run_tool("tools/validate_pmd_sprites.py")
        for d in RAW_SPRITE_DIRS + OPTIONAL_RAW_SPRITE_DIRS:
            p = ROOT / d
            if p.is_dir():
                skip_dirs.add(p)
        index_path = ROOT / "assets" / "atlas" / "index.json"
        if not index_path.is_file():
            print("ERROR: atlas build did not produce assets/atlas/index.json", file=sys.stderr)
            return None
        families = json.loads(index_path.read_text(encoding="utf-8")).get("families", {})
        if with_pmd:
            missing = [f for f in PMD_FAMILIES if f not in families]
            if missing:
                print(f"ERROR: the PMDCollab variant's atlas has no {', '.join(missing)} "
                      f"(tools/generate_sprite_atlases.py)", file=sys.stderr)
                return None
        else:
            stray = [f for f in families if f.startswith("pmd_")]
            if stray:
                print(f"ERROR: the HGSS-only variant's atlas still has {', '.join(stray)}", file=sys.stderr)
                return None

    zip_path = out_dir / f"wilds-of-hoenn-v{version}{spec['suffix']}.zip"
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
        return None

    with zipfile.ZipFile(zip_path) as z:
        names = z.namelist()
    problems = []
    if "manifest.json" not in names:
        problems.append("manifest.json not at ZIP root")
    if not args.no_atlas:
        leaked = [n for n in names if n.startswith("assets/enhanced_overworld/")
                  or n.startswith("assets/wilds_generated/true_size18/")
                  or n.startswith("assets/pmd/walk/")
                  or n.startswith("assets/pmd/idle/")
                  or n.startswith("assets/pmd/attack/")
                  or n.startswith("assets/pmd/hurt/")
                  or n.startswith("assets/pmd/portraits/")]
        if leaked:
            problems.append(f"atlas mode but {len(leaked)} raw sprite files leaked into the ZIP (first: {leaked[0]})")
    if not with_pmd:
        pmd_files = [n for n in names if n.startswith("assets/pmd/") or n.startswith("assets/atlas/pmd_")]
        if pmd_files:
            problems.append(f"the HGSS-only ZIP contains PMDCollab files (first: {pmd_files[0]})")
    else:
        for need in ("assets/pmd/index.json", "assets/pmd/portraits.json", "assets/pmd/CREDITS.txt"):
            if need not in names:
                problems.append(f"the PMDCollab ZIP is missing {need}")
    if problems:
        for p in problems:
            print(f"ERROR: {p}", file=sys.stderr)
        zip_path.unlink(missing_ok=True)
        return None

    mode = "per-file" if args.no_atlas else "atlas"
    size = zip_path.stat().st_size / 1e6
    print(f"wrote {zip_path}  ({len(names)} files, {size:.1f} MB, {mode} mode, mod id {mod_id})")
    return zip_path


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--variant", choices=("both", "hgss", "pmd"), default="both",
                    help="which release ZIP(s) to build (default: both)")
    ap.add_argument("--no-atlas", action="store_true", help="ship the raw per-file sheets instead of a baked atlas")
    ap.add_argument("--out-dir", default="dist",
                    help="directory (relative to the repo root) to write the ZIP(s) into, e.g. release")
    ap.add_argument("--no-pmd", action="store_true",
                    help="do not bake PMDCollab from SpriteCollab (an existing assets/pmd is still used by the pmd variant)")
    ap.add_argument("--rebake-pmd", action="store_true",
                    help="rewrite every PMDCollab sheet, not just the missing ones (after updating SpriteCollab)")
    args = ap.parse_args()

    manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
    version = manifest["version"]
    mod_id = manifest["id"]

    names = list(VARIANTS) if args.variant == "both" else [args.variant]
    if any(VARIANTS[n]["pmd"] for n in names) and not args.no_pmd:
        bake_pmd(args.rebake_pmd)

    out_dir = (ROOT / args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    built = []
    for name in names:
        path = build_variant(name, args, version, mod_id, out_dir)
        if path is None:
            return 1
        built.append(path)

    # assets/atlas/ (gitignored build output) is left matching the LAST variant built.
    print("built: " + ", ".join(p.name for p in built))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
