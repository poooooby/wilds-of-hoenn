#!/usr/bin/env python3
"""Bake PMDCollab (SpriteCollab) Walk and Idle sprites for the PMDCollab
Sprite Style.

SpriteCollab ships, per species, `sprite/<dex4>/AnimData.xml` plus
`<Anim>-Anim.png` sheets: one COLUMN per animation frame, 8 ROWS for the
directions (Down, DownRight, Right, UpRight, Up, UpLeft, Left, DownLeft --
confirmed against a real sheet), plus `<Anim>-Shadow.png` whose single white
pixel per frame marks the ground point. This tool keeps only what the engine
can use -- the Walk and Idle animations in the four cardinal directions
(Down, Right, Up, Left; PMD draws Left itself, nothing is mirrored) -- and
writes:

    assets/pmd/walk/<dex>-normal.png   (and -shiny.png when SpriteCollab has one)
    assets/pmd/idle/<dex>-normal.png
    assets/pmd/portraits/<dex>-normal.png  (and -shiny.png) emotion sheets, 40x40 cells
    assets/pmd/portraits.json          which emotions each species' sheet has, in column order
    assets/pmd/index.json              per-species frame size, durations, anchor
    assets/pmd/CREDITS.txt             attribution (CC BY-NC 4.0) for what was baked

Sheet layout of an output PNG: columns = animation frames, rows = the four
directions in the order DIRECTIONS below. Every cell has the same size: the
union of the opaque bounds of ALL frames of the animation (one shared crop
window -- never per-frame trimming, which makes animations jitter), plus a
transparent GUTTER on every side so neighbouring frames can never bleed into
each other when the sampler blends. Pixels are copied, never resampled.

The index also records a per-species `scale` (the true-size logic, see
true_size_scale: up only, never below 1).

The index records, per animation, `cw`/`ch` (cell size), `cols`, `durations`
(60 Hz ticks, straight from AnimData.xml) and `ax`/`ay` (the ground point
inside a cell; the renderer puts that point on the tile's feet position).

    python3 tools/generate_pmd_sprites.py
    python3 tools/generate_pmd_sprites.py --species 6,25,252 --force
    python3 tools/generate_pmd_sprites.py --src ../SpriteCollab

The output is gitignored (assets/pmd/); scripts/build-mod.py packs it into
the release atlas (tools/generate_sprite_atlases.py families pmd_walk and
pmd_idle) and ships index.json and CREDITS.txt as they are.
"""
from __future__ import annotations

import argparse
import json
import statistics
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
from form_art_map import FORM_ART, SHINY_DIR_OVERRIDE  # noqa: E402
DEFAULT_SRC = ROOT.parent / "SpriteCollab"
DEFAULT_OUT = ROOT / "assets" / "pmd"

INDEX_VERSION = 1
MAX_DEX = 1025
GUTTER = 2
ANIMS = ("walk", "idle")  # output names; SpriteCollab names are Walk / Idle
# Used by the overworld fights (the Battler's blows and a struck Pokemon's flinch);
# a species without one simply plays a rapid Idle instead, so they never fail a bake.
OPTIONAL_ANIMS = ("attack", "hurt")  # SpriteCollab: Attack (else Strike) / Hurt
ALL_ANIMS = ANIMS + OPTIONAL_ANIMS
WALK_FROM_IDLE_MAX_TICKS = 10  # see the Idle-stands-in-for-Walk case in main()

# Output direction -> source row (the 8-row PMD order: Down, DownRight,
# Right, UpRight, Up, UpLeft, Left, DownLeft).
DIRECTIONS = (("down", 0), ("right", 2), ("up", 4), ("left", 6))

# The shiny sprites live in <dex>/<form>/<shiny>: form 0, shiny 0001.
SHINY_SUBDIR = Path("0000") / "0001"
GROUND_MARKER = (255, 255, 255, 255)


def bake_targets(sprite_root: Path, wanted):
    """(dex, key, folder, shiny folder) for every sheet to bake: each base species
    (key "%03d"), then each alternate form SpriteCollab draws (key "%03d-<form>",
    see tools/form_art_map.py; a form whose folder is missing is left out and the
    game draws the base species instead)."""
    for dex in range(1, MAX_DEX + 1):
        if wanted is not None and dex not in wanted:
            continue
        folder = sprite_root / f"{dex:04d}"
        yield dex, f"{dex:03d}", folder, folder / SHINY_SUBDIR
    for dex, form, pmd_folder, _hgss in FORM_ART:
        if not pmd_folder or (wanted is not None and dex not in wanted):
            continue
        folder = sprite_root / f"{dex:04d}" / pmd_folder
        shiny = SHINY_DIR_OVERRIDE.get((dex, form)) or f"{pmd_folder}/0001"
        yield dex, f"{dex:03d}-{form}", folder, sprite_root / f"{dex:04d}" / shiny


def parse_anims(xml_path: Path) -> dict[str, dict]:
    """name -> {fw, fh, durations, source} with <CopyOf> resolved. `source`
    is the anim name whose PNG actually holds the frames."""
    root = ET.parse(xml_path).getroot()
    raw: dict[str, dict] = {}
    for el in root.iterfind("./Anims/Anim"):
        name = (el.findtext("Name") or "").strip()
        if not name:
            continue
        entry = {"copy": (el.findtext("CopyOf") or "").strip() or None}
        if el.find("FrameWidth") is not None:
            entry["fw"] = int(el.findtext("FrameWidth"))
            entry["fh"] = int(el.findtext("FrameHeight"))
            entry["durations"] = [int(d.text) for d in el.iterfind("./Durations/Duration")]
        raw[name] = entry

    def resolve(name: str, seen: tuple[str, ...] = ()) -> dict | None:
        e = raw.get(name)
        if e is None or name in seen:
            return None
        if e["copy"]:
            target = resolve(e["copy"], seen + (name,))
            return dict(target) if target else None
        if "fw" not in e or not e["durations"]:
            return None
        return {"fw": e["fw"], "fh": e["fh"], "durations": e["durations"], "source": name}

    return {name: r for name in raw if (r := resolve(name))}


def load_sheet(folder: Path, anim: str, kind: str) -> Image.Image | None:
    p = folder / f"{anim}-{kind}.png"
    return Image.open(p).convert("RGBA") if p.is_file() else None


def cell_of(sheet: Image.Image, fw: int, fh: int, col: int, row: int) -> Image.Image:
    return sheet.crop((col * fw, row * fh, (col + 1) * fw, (row + 1) * fh))


def ground_point(shadow: Image.Image | None, fw: int, fh: int, cols: int) -> tuple[float, float]:
    """Median of the white ground-marker pixel over the used cells (it is the
    same pixel in every cell of a well-formed sheet); frame bottom-centre if
    the sheet has none."""
    xs, ys = [], []
    if shadow is not None:
        px = shadow.load()
        for _name, row in DIRECTIONS:
            for col in range(cols):
                found = [(x, y)
                         for y in range(row * fh, (row + 1) * fh)
                         for x in range(col * fw, (col + 1) * fw)
                         if px[x, y] == GROUND_MARKER]
                if found:
                    xs.append(sum(p[0] for p in found) / len(found) - col * fw)
                    ys.append(sum(p[1] for p in found) / len(found) - row * fh)
    if not xs:
        return fw / 2.0, float(fh)
    return statistics.median(xs) + 0.5, statistics.median(ys) + 0.5


def union_bounds(sheets: list[Image.Image], fw: int, fh: int, cols: int):
    box = None
    for sheet in sheets:
        for _name, row in DIRECTIONS:
            for col in range(cols):
                b = cell_of(sheet, fw, fh, col, row).getchannel("A").getbbox()
                if b:
                    box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]),
                                                 max(box[2], b[2]), max(box[3], b[3]))
    return box


def compose(sheet: Image.Image, fw: int, fh: int, cols: int, box) -> Image.Image:
    x0, y0, x1, y1 = box
    cw, ch = (x1 - x0) + 2 * GUTTER, (y1 - y0) + 2 * GUTTER
    out = Image.new("RGBA", (cw * cols, ch * len(DIRECTIONS)), (0, 0, 0, 0))
    for r, (_name, row) in enumerate(DIRECTIONS):
        for col in range(cols):
            window = cell_of(sheet, fw, fh, col, row).crop(box)
            out.paste(window, (col * cw + GUTTER, r * ch + GUTTER), window)
    return out


def bake_anim(src_dir: Path, shiny_dir: Path | None, anim_name: str, meta: dict):
    """-> (entry, normal_sheet, shiny_sheet|None) or None when unusable."""
    source = meta["source"]
    fw, fh, durations = meta["fw"], meta["fh"], meta["durations"]
    cols = len(durations)
    sheet = load_sheet(src_dir, source, "Anim")
    if sheet is None or sheet.size != (fw * cols, fh * 8):
        return None
    shiny = None
    if shiny_dir is not None:
        shiny = load_sheet(shiny_dir, source, "Anim")
        if shiny is not None and shiny.size != sheet.size:
            shiny = None
    box = union_bounds([s for s in (sheet, shiny) if s is not None], fw, fh, cols)
    if box is None:
        return None
    ax, ay = ground_point(load_sheet(src_dir, source, "Shadow"), fw, fh, cols)
    cw, ch = (box[2] - box[0]) + 2 * GUTTER, (box[3] - box[1]) + 2 * GUTTER
    entry = {
        "cw": cw, "ch": ch, "cols": cols, "durations": durations,
        "ax": round(ax - box[0] + GUTTER, 2), "ay": round(ay - box[1] + GUTTER, 2),
    }
    return (entry, compose(sheet, fw, fh, cols, box),
            compose(shiny, fw, fh, cols, box) if shiny is not None else None)


# True size. The HGSS 18-frame bake (tools/generate_true_size_18frame.py) draws
# every species at its own real-world relative size; PMD art is usually
# larger than that, so the rule is UP ONLY: a species whose PMD sprite is
# clearly smaller than its HGSS sprite is drawn at a larger scale (quarter
# steps, at most TRUE_SIZE_MAX), everything else stays at exactly 1 -- PMD's
# own art is never downscaled. Needs the HGSS bake; without it every scale is 1.
HGSS_DIR = ROOT / "assets" / "wilds_generated" / "true_size18" / "hgss"
TRUE_SIZE_MAX = 2.0
TRUE_SIZE_MIN = 1.25  # below this the difference isn't worth uneven pixels


def median_height(sheet: Image.Image, cells: list[tuple[int, int]], cw: int, ch: int) -> float | None:
    hs = []
    for x, y in cells:
        box = sheet.crop((x, y, x + cw, y + ch)).getchannel("A").getbbox()
        if box:
            hs.append(box[3] - box[1])
    return statistics.median(hs) if hs else None


def true_size_scale(dex: int, key: str, walk_sheet: Image.Image, walk: dict) -> float:
    p = HGSS_DIR / f"{key}-normal.png"
    if not p.is_file():  # a form with no HGSS sheet of its own is sized like its base
        p = HGSS_DIR / f"{dex:03d}-normal.png"
    if not p.is_file():
        return 1.0
    hgss = Image.open(p).convert("RGBA")
    fh = hgss.height // 18
    ref = median_height(hgss, [(0, i * fh) for i in range(9)], hgss.width, fh)
    cw, ch, cols = walk["cw"], walk["ch"], walk["cols"]
    own = median_height(walk_sheet, [(c * cw, r * ch) for r in range(len(DIRECTIONS)) for c in range(cols)], cw, ch)
    if not ref or not own:
        return 1.0
    ratio = min(TRUE_SIZE_MAX, ref / own)
    ratio = round(ratio * 4) / 4
    return ratio if ratio >= TRUE_SIZE_MIN else 1.0


# Portraits. SpriteCollab keeps one 40x40 PNG per emotion in
# portrait/<dex4>/ (form 0, default gender; shiny in 0000/0001/, which may
# hold only the emotions that differ). Per species one sheet is baked:
# columns = the emotions that exist, in EMOTIONS order; the shiny sheet takes
# the shiny file for an emotion when there is one, else the normal one.
# Unflipped art only (the `^` files are pre-mirrored copies).
EMOTIONS = ("Normal", "Happy", "Joyous", "Inspired", "Worried", "Sad",
            "Surprised", "Pain", "Determined", "Angry", "Crying", "Dizzy",
            "Shouting", "Sigh", "Stunned", "Teary-Eyed")
PORTRAIT_SIZE = 40


def bake_portraits(src: Path, out: Path, dex: int, include_shiny: bool = False,
                   folder: Path | None = None):
    """-> (entry, normal_sheet, shiny_sheet|None) or None.

    Shiny portraits are skipped unless `include_shiny`: they are about half of
    all portrait art and a shiny Pokemon talking with its normal face is a
    fair trade. A species without a shiny sheet is served its normal one by
    SpriteSource.portraitCell (info.shiny == false), so nothing else changes."""
    folder = folder or src / "portrait" / f"{dex:04d}"
    shiny_dir = folder / SHINY_SUBDIR
    names, normal_imgs, shiny_imgs = [], [], []
    for emotion in EMOTIONS:
        p = folder / f"{emotion}.png"
        if not p.is_file():
            continue
        img = Image.open(p).convert("RGBA")
        if img.size != (PORTRAIT_SIZE, PORTRAIT_SIZE):
            continue
        sp = shiny_dir / f"{emotion}.png"
        shiny = Image.open(sp).convert("RGBA") if sp.is_file() else None
        if shiny is not None and shiny.size != img.size:
            shiny = None
        names.append(emotion)
        normal_imgs.append(img)
        shiny_imgs.append(shiny)
    if "Normal" not in names:
        return None
    has_shiny = include_shiny and any(s is not None for s in shiny_imgs)

    def sheet(images):
        out_img = Image.new("RGBA", (PORTRAIT_SIZE * len(images), PORTRAIT_SIZE), (0, 0, 0, 0))
        for i, im in enumerate(images):
            out_img.paste(im, (i * PORTRAIT_SIZE, 0))
        return out_img

    return ({"emotions": names, "shiny": has_shiny}, sheet(normal_imgs),
            sheet([s if s is not None else n for s, n in zip(shiny_imgs, normal_imgs)]) if has_shiny else None)


def read_names(src: Path) -> dict[str, str]:
    """Discord id -> display name, from credit_names.txt."""
    names: dict[str, str] = {}
    p = src / "credit_names.txt"
    if p.is_file():
        for line in p.read_text(encoding="utf-8", errors="replace").splitlines()[1:]:
            parts = line.split("\t")
            if len(parts) >= 2:
                names[parts[1].strip()] = parts[0].strip()
    return names


# Sprites added by hand from the PMDCollab Discord before they reached the public
# SpriteCollab repo. Their credits.txt files are free text (a handle, not the
# structured "CUR" log lines credit_line() reads), so the artists are named here
# -- and in THIRD_PARTY_NOTICES.md ("Sprites added manually"). Keep both in step.
# Used only when the folder has no structured credit line of its own.
MANUAL_CREDITS = {
    514: "butchcats",
    520: "Pokejavi, POWERCRISTAL",
    522: "Pokejavi, POWERCRISTAL",
    558: "JaiFain, POWERCRISTAL",
    564: "Pokejavi, Soulja",
    592: "Pokejavi, POWERCRISTAL",
    616: "Pokejavi",
    626: "Pokejavi, POWERCRISTAL",
    741: "baronessfaron",
    837: "baroness faron",
    838: "baroness faron",
    931: "Pokejavi, pi",
    943: "Gust, DavKriz",
    956: "rhys",
    962: "JaiFain",
    973: "pi",
    1008: "Delta L",
    1014: "JaiFain",
}


def credit_line(src: Path, dex: int, names: dict[str, str]) -> str | None:
    """Current (CUR) authors of the Walk/Idle art for one species (or, for a
    sprite added by hand before it reached SpriteCollab, MANUAL_CREDITS)."""
    p = src / "sprite" / f"{dex:04d}" / "credits.txt"
    if not p.is_file():
        return MANUAL_CREDITS.get(dex)
    who: list[str] = []
    for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.split("\t")
        if len(parts) < 5 or parts[2] != "CUR":
            continue
        files = {f.strip() for f in parts[4].split(",")}
        if not files & {"Walk", "Idle"}:
            continue
        author = names.get(parts[1].strip(), parts[1].strip())
        if author and author not in who:
            who.append(author)
    if who:
        return ", ".join(who)
    return MANUAL_CREDITS.get(dex)


def portrait_credit_line(src: Path, dex: int, names: dict[str, str]) -> str | None:
    """Current (CUR) authors of one species' portraits (portrait/<dex>/credits.txt)."""
    p = src / "portrait" / f"{dex:04d}" / "credits.txt"
    if not p.is_file():
        return None
    who: list[str] = []
    for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.split("\t")
        if len(parts) < 5 or parts[2] != "CUR":
            continue
        author = names.get(parts[1].strip(), parts[1].strip())
        if author and author not in who:
            who.append(author)
    return ", ".join(who) if who else None


CREDITS_HEADER = """PMDCollab SpriteCollab -- sprite credits
=======================================

The PMDCollab sprites in this mod are from the SpriteCollab project:
https://github.com/PMDCollab/SpriteCollab  (https://sprites.pmdcollab.org/)

All custom graphics not originating from official PMD games are licensed
under Attribution-NonCommercial 4.0 International
(http://creativecommons.org/licenses/by-nc/4.0/). Graphics originating from
the official games are (c) Spike Chunsoft / Nintendo / The Pokemon Company.
The sprites were repacked (Walk, Idle, Attack and Hurt only, cardinal
directions only, cropped and padded) -- no pixels were altered. The portraits
(40x40 faces) are copied unaltered.

Per-species artists (current sprites), by National Dex number:
"""

CREDITS_PORTRAITS_HEADER = """
Per-species artists (portraits), by National Dex number:
"""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", default=str(DEFAULT_SRC), help="SpriteCollab checkout")
    ap.add_argument("--out", default=str(DEFAULT_OUT))
    ap.add_argument("--species", default=None, help="comma list of dex numbers to limit to")
    ap.add_argument("--force", action="store_true", help="rewrite existing output files")
    ap.add_argument("--shiny-portraits", action="store_true",
                    help="also bake the shiny portrait sheets (about half of all portrait art); "
                         "by default a shiny Pokemon uses its normal portrait")
    args = ap.parse_args()

    src, out = Path(args.src), Path(args.out)
    sprite_root = src / "sprite"
    if not sprite_root.is_dir():
        print(f"ERROR: no SpriteCollab sprites at {sprite_root} (use --src)", file=sys.stderr)
        return 1
    wanted = {int(x) for x in args.species.split(",") if x.strip()} if args.species else None

    for anim in ALL_ANIMS:
        (out / anim).mkdir(parents=True, exist_ok=True)
    index_path = out / "index.json"
    index = {"version": INDEX_VERSION, "directions": [n for n, _ in DIRECTIONS], "gutter": GUTTER, "dex": {}}
    if index_path.is_file() and wanted is not None:
        try:
            index["dex"] = json.loads(index_path.read_text(encoding="utf-8")).get("dex", {})
        except (OSError, ValueError):
            pass

    names = read_names(src)
    credits: dict[int, str] = {}
    stats = {"baked": 0, "skipped_existing": 0, "no_sprites": 0, "unusable": 0}

    for dex, key, folder, shiny_dir in bake_targets(sprite_root, wanted):
        xml_path = folder / "AnimData.xml"
        if not xml_path.is_file():
            stats["no_sprites"] += 1
            continue
        try:
            anims = parse_anims(xml_path)
        except ET.ParseError as e:
            print(f"WARN dex {dex}: AnimData.xml unreadable ({e})", file=sys.stderr)
            stats["unusable"] += 1
            continue
        shiny_dir = shiny_dir if shiny_dir.is_dir() else None

        entry: dict = {}
        ok = True
        for anim in ANIMS:
            meta = anims.get(anim.capitalize())
            if meta is None and anim == "walk" and anims.get("Idle"):
                # A few species (Stunfisk, Toucannon, Iron Treads ...) ship an Idle
                # animation but no Walk. Their Idle frames stand in for the walk
                # loop, with each frame held at most WALK_FROM_IDLE_MAX_TICKS so a
                # moving sprite still visibly animates instead of sliding along on
                # a 40-tick hold. Flagged in the index (`walkFromIdle`).
                meta = dict(anims["Idle"])
                meta["durations"] = [min(d, WALK_FROM_IDLE_MAX_TICKS) for d in meta["durations"]]
                entry["walkFromIdle"] = True
            if meta is None:
                ok = False
                break
            result = bake_anim(folder, shiny_dir, anim.capitalize(), meta)
            if result is None:
                ok = False
                break
            info, normal, shiny = result
            entry[anim] = dict(info, shiny=shiny is not None)
            if anim == "walk":
                entry["scale"] = true_size_scale(dex, key, normal, info)
            normal_path = out / anim / f"{key}-normal.png"
            if args.force or not normal_path.exists():
                normal.save(normal_path, "PNG", optimize=True)
                if shiny is not None:
                    shiny.save(out / anim / f"{key}-shiny.png", "PNG", optimize=True)
            else:
                stats["skipped_existing"] += 1
        if ok:
            for anim in OPTIONAL_ANIMS:
                meta = anims.get(anim.capitalize())
                if meta is None and anim == "attack":
                    meta = anims.get("Strike")
                result = bake_anim(folder, shiny_dir, anim.capitalize(), meta) if meta else None
                normal_path = out / anim / f"{key}-normal.png"
                if result is None:
                    normal_path.unlink(missing_ok=True)
                    (out / anim / f"{key}-shiny.png").unlink(missing_ok=True)
                    continue
                info, normal, _shiny = result
                # fights are brief: the normal sheet serves shiny too (keeps the ZIP small)
                entry[anim] = dict(info, shiny=False)
                (out / anim / f"{key}-shiny.png").unlink(missing_ok=True)
                if args.force or not normal_path.exists():
                    normal.save(normal_path, "PNG", optimize=True)
        if not ok:
            for anim in ALL_ANIMS:  # never leave half a species behind
                for variant in ("normal", "shiny"):
                    (out / anim / f"{key}-{variant}.png").unlink(missing_ok=True)
            index["dex"].pop(key, None)
            stats["unusable"] += 1
            continue
        index["dex"][key] = entry
        line = credit_line(src, dex, names) if key == f"{dex:03d}" else None  # a form is credited with its base
        if line:
            credits[dex] = line
        stats["baked"] += 1

    index_path.write_text(json.dumps(index, separators=(",", ":"), sort_keys=True), encoding="utf-8")

    # portraits: assets/pmd/portraits/<dex>-<normal|shiny>.png + portraits.json
    # (kept OUTSIDE the portraits/ dir: that dir is atlas-packed and left out
    # of an atlas-mode ZIP, the index must always ship)
    (out / "portraits").mkdir(parents=True, exist_ok=True)
    pindex_path = out / "portraits.json"
    pindex = {"version": INDEX_VERSION, "size": PORTRAIT_SIZE, "dex": {}}
    if pindex_path.is_file() and wanted is not None:
        try:
            pindex["dex"] = json.loads(pindex_path.read_text(encoding="utf-8")).get("dex", {})
        except (OSError, ValueError):
            pass
    pstats = {"baked": 0, "none": 0}
    portrait_credits: dict[int, str] = {}
    targets = [(d, f"{d:03d}", src / "portrait" / f"{d:04d}")
               for d in range(1, MAX_DEX + 1) if wanted is None or d in wanted]
    # alternate forms (tools/form_art_map.py): one sheet per form that has its own
    # portrait folder; a form without one is shown with its base species' portrait
    targets += [(d, f"{d:03d}-{form}", src / "portrait" / f"{d:04d}" / folder)
                for d, form, folder, _hgss in FORM_ART
                if folder and (wanted is None or d in wanted) and not folder.count("/")]
    for dex, key, folder in targets:
        if not folder.is_dir():
            pstats["none"] += 1
            continue
        result = bake_portraits(src, out, dex, args.shiny_portraits, folder)
        if result is None:
            pstats["none"] += 1
            continue
        entry, normal, shiny = result
        pindex["dex"][key] = entry
        pline = portrait_credit_line(src, dex, names) if key == f"{dex:03d}" else None
        if pline:
            portrait_credits[dex] = pline
        if shiny is None:  # never leave an earlier bake's shiny sheet behind
            (out / "portraits" / f"{key}-shiny.png").unlink(missing_ok=True)
        normal_path = out / "portraits" / f"{key}-normal.png"
        if args.force or not normal_path.exists():
            normal.save(normal_path, "PNG", optimize=True)
            if shiny is not None:
                shiny.save(out / "portraits" / f"{key}-shiny.png", "PNG", optimize=True)
        pstats["baked"] += 1
    pindex_path.write_text(json.dumps(pindex, separators=(",", ":"), sort_keys=True), encoding="utf-8")
    print(f"portraits: {pstats['baked']} species baked, {pstats['none']} without usable portraits")
    if wanted is None:
        body = "".join(f"{d:04d}  {credits[d]}\n" for d in sorted(credits))
        pbody = "".join(f"{d:04d}  {portrait_credits[d]}\n" for d in sorted(portrait_credits))
        (out / "CREDITS.txt").write_text(CREDITS_HEADER + body + CREDITS_PORTRAITS_HEADER + pbody,
                                         encoding="utf-8")
    print(f"baked {stats['baked']} species ({len(index['dex'])} in index), "
          f"{stats['skipped_existing']} sheets kept (--force to rewrite), "
          f"{stats['no_sprites']} without PMD sprites, {stats['unusable']} unusable")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
