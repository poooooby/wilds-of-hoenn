#!/usr/bin/env python3
"""Bakes 18-frame walker sheets (stand/walk-A/walk-B/run-base/run-A/run-B per
direction) for HGSS/PokeMMO-style rendering, from the raw 4x4-grid source art
tools/copy_wilds_assets.py copies in from the sibling Wilds of Kanto Revival
checkout.

Source grid convention (one PNG per species+form+variant, confirmed by
opening sample files directly): 4 columns x 4 rows, cell size = image size /
4. Rows are directions: 0=down, 1=left, 2=right (always unused -- visually a
completely different, irrelevant pose in every source file checked; the
real player/NPC never draws a stored right frame either, it always mirrors
left), 3=up. Column 0 is the stand/idle pose. Columns 1-3 are three
candidate poses with no guaranteed fixed meaning across species (confirmed
against Wilds of Kanto Revival's own tooling, which has a `pick_walk_column`
auto-detection step for exactly this reason) -- see detect_roles() below for
how this script decides which is which, per species, per direction.

Output: assets/wilds_generated/true_size18/{hgss,swimming,levitates}/
<dex>-{normal,shiny}.png -- a plain vertical strip, NATIVE per-species frame
size (frame height = image height / 18, frame width = the strip's own
width), no forced 16x16, no scaling, no separate geometry JSON.
lib/actor_renderer.lua already reads real frame dimensions off the loaded
image rather than predicting them from an authored table, and this keeps
that.

Frame order (18 total), matching the real Gen 3 player/NPC's own layout
(sapphire/data/generated/gba/ow/manifest.lua graphics id 0, decoded via
src/core/game3/ow_sprites.lua's STAND/WALK_A/WALK_B/RUN_BASE/RUN_A/RUN_B
tables in the gen1recomp engine):
    0  stand-down     3  walk-down-A   9  run-down-base
    1  stand-up       4  walk-down-B  10  run-down-A
    2  stand-left     5  walk-up-A    11  run-down-B
                       6  walk-up-B   12  run-up-base
                       7  walk-left-A 13  run-up-A
                       8  walk-left-B 14  run-up-B
                                      15  run-left-base
                                      16  run-left-A
                                      17  run-left-B

There is no dedicated running art (confirmed: the source only has walking
poses). Per the user's own mapping, run-A and run-B reuse walk-B's and
walk-A's pixels respectively (baked once, here -- not a runtime trick):
    run-base = the detected "odd one out" candidate column
    run-A    = walk-B's pixels (same column as walk-B)
    run-B    = walk-A's pixels (same column as walk-A)

detect_roles() heuristic: for the 3 non-stand candidate columns, compute all
3 pairwise pixel-difference magnitudes (PIL ImageChops.difference, summed).
The two columns with the SMALLEST pairwise difference are treated as a
walk-A/walk-B pair (most similar to each other -- a plausible two-phase gait
oscillating around a shared base); the third (the one not in that closest
pair) becomes run-base. This is a heuristic, not a certainty -- run with
--report first and spot-check a sample of species against the real source
images before trusting it across the full dex range. --species-override
lets you pin specific species by hand (same escape-hatch idea as Wilds of
Kanto Revival's own MANUAL_OVERRIDES in generate_true_size_runtime.py).

Usage:
    python3 tools/generate_true_size_18frame.py --report               # inspect choices, writes nothing
    python3 tools/generate_true_size_18frame.py                        # bake everything
    python3 tools/generate_true_size_18frame.py --kind hgss --species 1,4,7
    python3 tools/generate_true_size_18frame.py --species-override 352:2,1,3
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageStat

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
from form_art_map import FORM_ART, GEN9_FOLLOWERS  # noqa: E402

FORM_PREFERENCE = ("b", "f", "m")  # "both" gender art preferred; gendered-only species fall back
DIRECTION_ROW = {"down": 0, "left": 1, "up": 3}  # row 2 ("right") is never read
GRID_COLS, GRID_ROWS = 4, 4

KINDS = ("hgss", "swimming", "levitates")

# Canonical 18-frame order -- see module docstring. (direction, role).
OUTPUT_FRAMES = [
    ("down", "stand"), ("up", "stand"), ("left", "stand"),
    ("down", "walkA"), ("down", "walkB"),
    ("up", "walkA"), ("up", "walkB"),
    ("left", "walkA"), ("left", "walkB"),
    ("down", "runBase"), ("down", "runA"), ("down", "runB"),
    ("up", "runBase"), ("up", "runA"), ("up", "runB"),
    ("left", "runBase"), ("left", "runA"), ("left", "runB"),
]
FRAME_COUNT = len(OUTPUT_FRAMES)


def source_dir(kind: str, variant: str) -> Path:
    if kind == "hgss":
        return ROOT / "assets/enhanced_overworld/followsprites"
    return ROOT / "assets/enhanced_overworld/water_sprites" / kind / variant


def source_filename(kind: str, dex: int, form: str, variant: str) -> str:
    letter = "n" if variant == "normal" else "s"
    prefix = "" if kind == "hgss" else f"{kind}_"
    return f"{prefix}{dex:03d}-{form}-{letter}.png"


def find_source(kind: str, dex: int, variant: str) -> Path | None:
    d = source_dir(kind, variant)
    for form in FORM_PREFERENCE:
        p = d / source_filename(kind, dex, form, variant)
        if p.is_file():
            return p
    return None


def known_dexes(kind: str) -> list[int]:
    """Every dex with normal source art for this kind, from the real files
    on disk (not a hardcoded range -- water kinds cover fewer species)."""
    d = source_dir(kind, "normal")
    if not d.is_dir():
        return []
    seen = set()
    for p in d.glob("*.png"):
        stem = p.stem
        # strip the kind_ prefix (water kinds) and any trailing _suffix
        # (e.g. swimming_003-b-n_female)
        core = stem.split("_", 1)[1] if kind != "hgss" and stem.startswith(f"{kind}_") else stem
        head = core.split("-", 1)[0]
        if head.isdigit():
            seen.add(int(head))
    return sorted(seen)


def crop_tile(im: Image.Image, col: int, row: int, cw: int, ch: int) -> Image.Image:
    x0, y0 = col * cw, row * ch
    return im.crop((x0, y0, x0 + cw, y0 + ch))


def pixel_distance(a: Image.Image, b: Image.Image) -> float:
    a, b = a.convert("RGBA"), b.convert("RGBA")
    diff = ImageChops.difference(a, b)
    return float(sum(ImageStat.Stat(diff).sum))


def detect_roles(tiles: dict[int, Image.Image], override: tuple[int, int, int] | None):
    """tiles = {1: cand, 2: cand, 3: cand} (grid columns 1-3, column 0 is
    stand and handled separately). Returns (walkA_col, walkB_col,
    runBase_col). `override`, if given, is trusted directly."""
    if override:
        return override
    d12 = pixel_distance(tiles[1], tiles[2])
    d13 = pixel_distance(tiles[1], tiles[3])
    d23 = pixel_distance(tiles[2], tiles[3])
    ranked = sorted([(d12, 1, 2, 3), (d13, 1, 3, 2), (d23, 2, 3, 1)], key=lambda t: t[0])
    # Some source sheets repeat their frames (A, A, B, B). The closest pair is
    # then the IDENTICAL pair, which made walkA == walkB and left the sprite
    # with no walk animation at all (the old 6-frame look). Prefer the closest
    # pair that actually differs.
    distinct = [r for r in ranked if r[0] > 0]
    _dist, walk_a, walk_b, run_base = (distinct or ranked)[0]
    return walk_a, walk_b, run_base


def detect_roles_shared(per_direction: list[dict[int, Image.Image]]):
    """One (walkA, walkB, runBase) column mapping for ALL directions of a
    WATER sheet, in the source's natural column order: stand = col 0, walk
    A/B = cols 1 and 2, run base = col 3 -- the order the art is drawn as one
    flap/swim cycle. The first candidate whose walk pair differs in every
    direction wins (so repeated-frame sheets, e.g. A A B B, still animate);
    failing that, the first that differs in at least one.

    Not the closest-pair heuristic of detect_roles(): for flyers the two
    NEAREST columns are the near-identical wings-spread frames, and picking
    them per direction gave Charizard's levitates art (2, 3) for up/down but
    (1, 2) for left/right -- moving up/down held spread wings against a
    raised-wings stand frame and visibly snapped."""
    cands = [(1, 2, 3), (1, 3, 2), (2, 3, 1)]
    dists = [[pixel_distance(t[a], t[b]) for t in per_direction] for a, b, _ in cands]
    for (a, b, run), d in zip(cands, dists):
        if all(x > 0 for x in d):
            return a, b, run
    for (a, b, run), d in zip(cands, dists):
        if any(x > 0 for x in d):
            return a, b, run
    return cands[0]


# --- Water art scale -------------------------------------------------------
# The swimming/levitates source sheets are drawn on 64px cells, roughly twice
# the HGSS land art's scale, so baking them raw draws a water Charizard at
# about double its land size. Mirrors Wilds of Kanto Revival's "perceived
# size" match (tools/generate_true_size_runtime.py): shrink the water art
# (nearest-neighbour, never upscaled) until its median opaque pixel area
# equals the same species' LAND sprite, times WATER_PERCEIVED_TARGET. Land is
# the hgss sheet in the same out-root, baked first (KINDS order).
#
# Tried and reverted: a width cap on top of this, and area-averaged (BOX)
# resampling. The artefacts came from cropping each sheet TIGHT with no margin
# (see WATER_PAD), not from the nearest-neighbour choice itself.
WATER_PERCEIVED_TARGET = 0.97
# frames 0-8: stand + walkA/walkB for down/up/left (see OUTPUT_FRAMES)
METRIC_FRAMES = range(9)


def median_opaque_area(sheet: Image.Image) -> float | None:
    """Median per-frame opaque pixel count over METRIC_FRAMES."""
    ch = sheet.height // FRAME_COUNT
    areas = []
    for i in METRIC_FRAMES:
        alpha = sheet.crop((0, i * ch, sheet.width, (i + 1) * ch)).getchannel("A")
        n = sum(alpha.point(lambda a: 1 if a > 0 else 0).histogram()[1:])
        if n:
            areas.append(n)
    if not areas:
        return None
    areas.sort()
    return float(areas[len(areas) // 2])


def land_reference(out_root: Path, dex: int, variant: str) -> Image.Image | None:
    p = out_root / "hgss" / f"{dex:03d}-{variant}.png"
    return Image.open(p).convert("RGBA") if p.is_file() else None


def water_scale(sheet: Image.Image, land: Image.Image | None) -> float:
    if land is None:
        return 1.0
    water_area, land_area = median_opaque_area(sheet), median_opaque_area(land)
    if not water_area or not land_area:
        return 1.0
    return min(1.0, WATER_PERCEIVED_TARGET * (land_area / water_area) ** 0.5)


# Transparent border around every baked water frame. Frames are stacked
# vertically in one sheet and drawn through quads, so opaque pixels on a
# frame's first/last row bleed into the neighbouring frame whenever the
# sampler blends (non-integer camera scale / sub-pixel positions) -- the
# "bottom of the previous frame showing at the top" artefact. Same 2px
# safety margin as Wilds of Kanto Revival's TRUE_SIZE_PADDING. The BOTTOM
# margin is mirrored in lib/sprite_source.lua (WATER_BOTTOM_PAD) so the
# renderer can keep the feet flush with the tile.
WATER_PAD = 2
# Scales this close to 0.5 snap to exactly 0.5 (Kanto's snap_friendly_scales):
# a clean 2:1 reduction instead of an uneven fractional one.
SNAP_HALF_TOLERANCE = 0.1


def scale_and_trim(sheet: Image.Image, scale: float) -> Image.Image:
    """Kanto's compose_native_sheet recipe: ONE shared crop window (union of
    every frame's opaque bounds) cut at native resolution, ONE nearest-
    neighbour resize of that window, the same paste offset for every frame
    (no per-frame trim/centering, so no jitter), plus WATER_PAD of
    transparent margin. The window origin is aligned to even pixels so a 0.5
    reduction of 2x-upscaled source art stays pixel-exact."""
    ch = sheet.height // FRAME_COUNT
    tiles = [sheet.crop((0, i * ch, sheet.width, (i + 1) * ch)) for i in range(FRAME_COUNT)]
    union = None
    for t in tiles:
        b = t.getchannel("A").getbbox()
        if b:
            union = b if union is None else (min(union[0], b[0]), min(union[1], b[1]),
                                             max(union[2], b[2]), max(union[3], b[3]))
    if union is None:
        union = (0, 0, sheet.width, ch)
    x0, y0 = union[0] - union[0] % 2, union[1] - union[1] % 2
    x1 = min(sheet.width, union[2] + union[2] % 2)
    y1 = min(ch, union[3] + union[3] % 2)
    cw, chh = x1 - x0, y1 - y0
    if abs(scale - 0.5) <= SNAP_HALF_TOLERANCE:
        scale = 0.5
    resized = scale < 1.0
    nw = max(1, round(cw * scale)) if resized else cw
    nh = max(1, round(chh * scale)) if resized else chh
    fw, fh = nw + 2 * WATER_PAD, nh + 2 * WATER_PAD
    out = Image.new("RGBA", (fw, fh * FRAME_COUNT), (0, 0, 0, 0))
    for i, t in enumerate(tiles):
        window = t.crop((x0, y0, x1, y1))
        if resized:
            window = window.resize((nw, nh), Image.NEAREST)
        out.paste(window, (WATER_PAD, i * fh + WATER_PAD), window)
    return out


def halve(im: Image.Image) -> Image.Image:
    """2x box downscale of RGBA pixel art: colours weighted by alpha so transparent
    pixels do not darken the edges, alpha then cut hard (>= half) to stay crisp.
    The Gen 9 follower pack draws twice the size of the Wilds grids."""
    w, h = im.size
    small = im.resize((w // 2, h // 2), Image.BOX)  # alpha = coverage
    src, out = im.load(), Image.new("RGBA", small.size)
    px = out.load()
    for y in range(h // 2):
        for x in range(w // 2):
            r = g = b = a = 0
            for dy in (0, 1):
                for dx in (0, 1):
                    pr, pg, pb, pa = src[x * 2 + dx, y * 2 + dy]
                    r, g, b, a = r + pr * pa, g + pg * pa, b + pb * pa, a + pa
            if a >= 2 * 255:  # at least half covered
                px[x, y] = (round(r / a), round(g / a), round(b / a), 255)
    return out


def bake_species(kind: str, dex: int, variant: str, override, report: bool,
                 out_root: Path | None = None, src: Path | None = None) -> dict | None:
    src = src or find_source(kind, dex, variant)
    if not src:
        return None
    im = Image.open(src).convert("RGBA")
    if GEN9_FOLLOWERS in src.parents or GEN9_FOLLOWERS.with_name(GEN9_FOLLOWERS.name + " shiny") in src.parents:
        im = halve(im)
    w, h = im.size
    cw, ch = w // GRID_COLS, h // GRID_ROWS

    frames = {}  # (direction, role) -> Image
    detected = {}  # direction -> (walkA_col, walkB_col, runBase_col), for the report
    all_tiles = {d: {c: crop_tile(im, c, row, cw, ch) for c in range(GRID_COLS)}
                 for d, row in DIRECTION_ROW.items()}
    shared = None
    if kind != "hgss" and not override:
        shared = detect_roles_shared(list(all_tiles.values()))
    for direction, row in DIRECTION_ROW.items():
        tiles = all_tiles[direction]
        walk_a, walk_b, run_base = shared or detect_roles({1: tiles[1], 2: tiles[2], 3: tiles[3]}, override)
        detected[direction] = (walk_a, walk_b, run_base)
        frames[(direction, "stand")] = tiles[0]
        frames[(direction, "walkA")] = tiles[walk_a]
        frames[(direction, "walkB")] = tiles[walk_b]
        frames[(direction, "runBase")] = tiles[run_base]
        frames[(direction, "runA")] = tiles[walk_b]  # reuse: run-A = walk-B's art
        frames[(direction, "runB")] = tiles[walk_a]  # reuse: run-B = walk-A's art

    if report:
        return {"src": src, "cell": (cw, ch), "detected": detected}

    sheet = Image.new("RGBA", (cw, ch * FRAME_COUNT), (0, 0, 0, 0))
    for i, key in enumerate(OUTPUT_FRAMES):
        sheet.paste(frames[key], (0, i * ch))
    scale = 1.0
    if kind != "hgss" and out_root is not None:
        scale = water_scale(sheet, land_reference(out_root, dex, variant))
        sheet = scale_and_trim(sheet, scale)
        cw, ch = sheet.width, sheet.height // FRAME_COUNT
    return {"image": sheet, "cell": (cw, ch), "detected": detected, "scale": scale}


# (kind, dex) -> (walkA_col, walkB_col, runBase_col). Pins a known-bad
# auto-detection permanently, so a future full rebake (no --species-override
# on the command line) doesn't regress it -- same escape-hatch idea as
# Wilds of Kanto Revival's own MANUAL_OVERRIDES, confirmed by eye against
# the raw source grid, not re-guessed. Keyed by (kind, dex), NOT dex alone
# -- different kinds are independent source art with their own column
# layouts (confirmed: Charizard's levitates grid auto-detects a DIFFERENT
# or column mapping than its hgss grid, and is internally consistent
# across all 3 directions there -- correct as detected, do not touch).
MANUAL_OVERRIDES: dict[tuple[str, int], tuple[int, int, int]] = {
    # Charizard (dex 6), hgss/land only, "up" row: auto-detect paired the
    # wings-folded extreme pose (col 2) with a wings-spread pose (col 3) as
    # the walk-A/walk-B cycle, producing a visible snap between a folded
    # and a spread-wing pose every step. down/left correctly pair cols 1 &
    # 3 (both subtle wings-spread variants) and reserve col 2 (folded) for
    # running only -- forcing that same (1, 3, 2) mapping onto "up" fixes
    # it to match.
    ("hgss", 6): (1, 3, 2),
}


def parse_overrides(raw: str) -> dict[int, tuple[int, int, int]]:
    out = {}
    if not raw:
        return out
    for entry in raw.split(";"):
        entry = entry.strip()
        if not entry:
            continue
        dex_str, cols = entry.split(":", 1)
        a, b, c = (int(x) for x in cols.split(","))
        out[int(dex_str)] = (a, b, c)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--kind", default="all", help="hgss, swimming, levitates, or all (comma list ok)")
    ap.add_argument("--species", default=None, help="comma list of dex numbers to limit to")
    ap.add_argument("--max-species", type=int, default=None, help="only dex <= this")
    ap.add_argument("--species-override", default="",
                     help="dex:col1,col2,col3[;dex:col1,col2,col3...] -- pins walkA,walkB,runBase "
                          "source columns (1-3) for specific dex, skipping auto-detection")
    ap.add_argument("--force", action="store_true", help="rewrite existing output files")
    ap.add_argument("--report", action="store_true", help="print detected roles, write nothing")
    ap.add_argument("--out-root", default=str(ROOT / "assets/wilds_generated/true_size18"))
    args = ap.parse_args()

    kinds = list(KINDS) if args.kind == "all" else [k.strip() for k in args.kind.split(",") if k.strip()]
    unknown = [k for k in kinds if k not in KINDS]
    if unknown:
        print(f"unknown kind(s): {unknown}; known: {KINDS}", file=sys.stderr)
        return 2

    cli_overrides = parse_overrides(args.species_override)
    species_filter = None
    if args.species:
        species_filter = {int(x) for x in args.species.split(",") if x.strip()}

    out_root = Path(args.out_root)
    stats = {"written": 0, "skipped_existing": 0, "missing_source": 0}

    for kind in kinds:
        dexes = known_dexes(kind)
        if species_filter is not None:
            dexes = [d for d in dexes if d in species_filter]
        if args.max_species is not None:
            dexes = [d for d in dexes if d <= args.max_species]

        out_dir = out_root / kind
        if not args.report:
            out_dir.mkdir(parents=True, exist_ok=True)

        for dex in dexes:
            for variant in ("normal", "shiny"):
                # CLI takes precedence (useful for trying a new override
                # before committing it to MANUAL_OVERRIDES above).
                override = cli_overrides.get(dex) or MANUAL_OVERRIDES.get((kind, dex))
                result = bake_species(kind, dex, variant, override, args.report, out_root)
                if result is None:
                    stats["missing_source"] += 1
                    continue

                if args.report:
                    for direction, (wa, wb, rb) in result["detected"].items():
                        print(f"{kind:9s} dex={dex:4d} {variant:6s} {direction:5s} "
                              f"walkA=col{wa} walkB=col{wb} runBase=col{rb} "
                              f"(src={result['src'].name}, cell={result['cell']})")
                    continue

                out_path = out_dir / f"{dex:03d}-{variant}.png"
                if out_path.exists() and not args.force:
                    stats["skipped_existing"] += 1
                    continue
                result["image"].save(out_path, "PNG", optimize=True)
                stats["written"] += 1

    # Alternate forms (tools/form_art_map.py): HGSS land art only, written as
    # <dex3>-<form>-<normal|shiny>.png beside the base sheets. A form with no raw
    # grid is simply absent and the game draws its base species.
    if "hgss" in kinds:
        out_dir = out_root / "hgss"
        for dex, form, _pmd, hgss_variant in FORM_ART:
            if hgss_variant is None or (species_filter is not None and dex not in species_filter):
                continue
            for variant in ("normal", "shiny"):
                letter = "n" if variant == "normal" else "s"
                if isinstance(hgss_variant, str):  # a file of the Gen 9 follower pack
                    folder = GEN9_FOLLOWERS if variant == "normal" else GEN9_FOLLOWERS.with_name(GEN9_FOLLOWERS.name + " shiny")
                    src = folder / hgss_variant
                else:
                    src = source_dir("hgss", variant) / f"{dex:03d}-b-{letter}-{hgss_variant}.png"
                if not src.is_file():
                    stats["missing_source"] += 1
                    continue
                result = bake_species("hgss", dex, variant, None, args.report, out_root, src=src)
                if result is None or args.report:
                    continue
                out_dir.mkdir(parents=True, exist_ok=True)
                out_path = out_dir / f"{dex:03d}-{form}-{variant}.png"
                if out_path.exists() and not args.force:
                    stats["skipped_existing"] += 1
                    continue
                result["image"].save(out_path, "PNG", optimize=True)
                stats["written"] += 1

    if args.report:
        print("\n(report mode: nothing written)")
    else:
        print(f"\nwrote {stats['written']} files, skipped {stats['skipped_existing']} existing "
              f"(--force to rewrite), {stats['missing_source']} had no source art")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
