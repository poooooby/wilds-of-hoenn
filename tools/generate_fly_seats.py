#!/usr/bin/env python3
"""Where the player sits on each Fly Mount (lib/fly_mount.lua): writes lib/fly_seats.lua.

When you use Fly, the Pokemon that knows it carries you (the engine's bird replaced). The
engine puts the player 8 px above the bird's centre; the mount is drawn so its SEAT -- a point
of its art -- lands under the player's sprite (its bottom centre, the seated rider's lower
edge). A seat is in the art's own px:

  pmd   the "mount" sheet (assets/pmd/mount/<key>-normal.png: the down-left flight, one row,
        tools/generate_pmd_sprites.py mount_meta), cell px
  hgss  the land sheet's left-facing walk frame (assets/wilds_generated/true_size18/hgss,
        frame 7 of 18), frame px

A seat is set on the FIRST frame: automatically the column of the art's centre (its opaque
pixels' median x) and the top of the art there, `SINK` px in -- the rider astride its back (a
small Pokemon's top is its head, which is where a rider that does not fit its back goes) --
or by SEATS (the 2026-11 seat audit, every mount checked with the rider drawn on it), a
fraction of the first frame's art box: (fx, fy) = x0 + fx * w, y0 + fy * h. Rayquaza and the
like sit the rider on the head. Every other frame's seat follows the body under it: the patch
of art under the seat is found again in that frame (the best match within TRACK px), so a
Pokemon swooping about in its animation (Ho-Oh, Roaring Moon) carries the rider along.

    python3 tools/generate_fly_seats.py                  # write lib/fly_seats.lua
    python3 tools/generate_fly_seats.py --review DIR     # + contact sheets with the rider on
"""
from __future__ import annotations

import argparse
import json
import re
import statistics
import sys
import zlib
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
PMD = ROOT / "assets" / "pmd"
HGSS = ROOT / "assets" / "wilds_generated" / "true_size18" / "hgss"
OUT = ROOT / "lib" / "fly_seats.lua"
HGSS_FRAMES = 18
HGSS_LEFT = (7, 8)  # walk A / B facing left (lib/actor_renderer.lua FRAME_INDEX_18)
SINK = 5            # px the rider's lower edge sits into the body below its top
COLUMN = 2          # half width of the column the top is read in

sys.path.insert(0, str(ROOT / "tools"))
from generate_pmd_sprites import FLY_LEARNERS, NO_FLIGHT  # noqa: E402

# (style, key) -> (fx, fy) on the art's box; key = the index key ("6", "641-therian")
SEATS: dict[tuple[str, str], tuple[float, float]] = {
    ("pmd", "6"): (0.45, 0.56),         # Charizard: its back behind the neck, not the raised wings
    ("pmd", "142"): (0.5, 0.42),        # Aerodactyl: between its wings, not on a wing tip
    ("pmd", "250"): (0.5, 0.62),        # Ho-Oh: its body between the wings, not a wing
    ("pmd", "357"): (0.42, 0.32),       # Tropius: its back, under the leaves
    ("pmd", "384"): (0.35, 0.33),       # Rayquaza: on its head (the user's call)
    ("pmd", "646-black"): (0.42, 0.42),  # Black Kyurem: its back, not the spike
    ("pmd", "890"): (0.55, 0.42),       # Eternatus: behind its head
    ("pmd", "1005"): (0.45, 0.4),       # Roaring Moon: between its wings
    ("hgss", "384"): (0.28, 0.2),       # Rayquaza: on its head
    ("hgss", "644"): (0.5, 0.36),       # Zekrom: its back, not a wing tip
    ("hgss", "646-black"): (0.5, 0.36),  # Black Kyurem: its back, not the spike
}
TRACK = 14       # px searched each way for the body under the seat in another frame
PATCH = (6, 2, 9)  # the patch matched: half width, rows above the seat, rows below


def opaque_box(cells):
    box = None
    for c in cells:
        b = c.getchannel("A").getbbox()
        if b:
            box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    return box


def auto_seat(cells) -> tuple[float, float] | None:
    xs = []
    for c in cells:
        a = c.getchannel("A").load()
        w, h = c.size
        pts = [x for y in range(h) for x in range(w) if a[x, y]]
        if pts:
            xs.append(statistics.median(pts))
    if not xs:
        return None
    cx = round(statistics.median(xs))
    tops = []
    for c in cells:
        a = c.getchannel("A").load()
        w, h = c.size
        top = next((y for y in range(h) for x in range(max(0, cx - COLUMN), min(w, cx + COLUMN + 1)) if a[x, y]), None)
        if top is not None:
            tops.append(top)
    if not tops:
        return None
    return cx + 0.5, statistics.median(tops) + SINK


def pmd_cells(key: str, entry: dict):
    name = key if "-" in key else f"{int(key):03d}"
    p = PMD / "mount" / f"{name}-normal.png"
    if not p.is_file():
        return None
    im = Image.open(p).convert("RGBA")
    cw, ch = entry["cw"], entry["ch"]
    return [im.crop((c * cw, 0, (c + 1) * cw, ch)) for c in range(entry["cols"])]


def hgss_cells(key: str):
    p = HGSS / f"{key}-normal.png"
    if not p.is_file():
        return None
    im = Image.open(p).convert("RGBA")
    fh = im.height // HGSS_FRAMES
    return [im.crop((0, f * fh, im.width, (f + 1) * fh)) for f in HGSS_LEFT]


def track(cells, sx: float, sy: float) -> list[tuple[float, float]]:
    """The seat (sx, sy) of the first frame in every frame: the patch of art under it found
    again (least squared difference over RGBA, within TRACK px), so the rider rides the
    body as it moves in the animation."""
    import numpy as np
    arrs = [np.asarray(c, dtype=np.float32) for c in cells]
    h, w = arrs[0].shape[:2]
    hw, up, down = PATCH
    x, y = int(sx), int(sy)
    x0, x1, y0, y1 = max(0, x - hw), min(w, x + hw + 1), max(0, y - up), min(h, y + down + 1)
    ref = arrs[0][y0:y1, x0:x1]
    out = [(sx, sy)]
    prev = (0, 0)
    for a in arrs[1:]:
        best, bd = prev, None
        for dy in range(-TRACK, TRACK + 1):
            for dx in range(-TRACK, TRACK + 1):
                if y0 + dy < 0 or y1 + dy > h or x0 + dx < 0 or x1 + dx > w:
                    continue
                d = float(((a[y0 + dy:y1 + dy, x0 + dx:x1 + dx] - ref) ** 2).sum())
                # ties (and near-ties) go to the smaller move from the last frame
                d += 40.0 * ((dx - prev[0]) ** 2 + (dy - prev[1]) ** 2)
                if bd is None or d < bd:
                    best, bd = (dx, dy), d
        prev = best
        out.append((sx + best[0], sy + best[1]))
    return out


def seat_for(style: str, key: str, cells):
    """-> (frames: [(x, y)] per frame, how) or None."""
    over = SEATS.get((style, key))
    if over is not None:
        x0, y0, x1, y1 = cells[0].getchannel("A").getbbox()
        sx, sy, how = x0 + over[0] * (x1 - x0), y0 + over[1] * (y1 - y0), "set"
    else:
        s = auto_seat(cells[:1])
        if not s:
            return None
        (sx, sy), how = s, "auto"
    return track(cells, sx, sy), how


def rider_sprite():
    """The seated player facing left (Brendan's ride frame), for the review sheets."""
    base = ROOT.parent / "gen1recomp" / "emerald" / "data" / "generated" / "gba" / "ow" / "2.rgba"
    if not base.is_file():
        return None
    d = zlib.decompress(base.read_bytes())
    im = Image.frombytes("RGBA", (32, len(d) // 128), d)
    return im.crop((0, 64, 32, 96))


def review(rows, out_dir: Path, tag: str):
    rider = rider_sprite()
    Z = 3
    tiles = []
    for key, cells, (frames, how) in rows:
        pics = []
        sx, sy = frames[0]
        for i in sorted({0, len(cells) // 3, (2 * len(cells)) // 3}):
            c = cells[i]
            fx, fy = frames[i]
            w, h = c.size
            canvas = Image.new("RGBA", (w + 32, h + 40), (80, 130, 80, 255))
            ox, oy = 16, 32
            canvas.alpha_composite(c, (ox, oy))
            if rider is not None:
                canvas.alpha_composite(rider, (int(ox + fx - 16), int(oy + fy - 32)))
            pics.append(canvas)
        grid = Image.new("RGBA", (cells[0].width + 32, cells[0].height + 40), (60, 60, 60, 255))
        grid.alpha_composite(cells[0], (16, 32))
        g = ImageDraw.Draw(grid)
        x0, y0, x1, y1 = opaque_box(cells)
        for f in (0.25, 0.5, 0.75):
            g.line((16 + x0 + f * (x1 - x0), 32 + y0, 16 + x0 + f * (x1 - x0), 32 + y1), fill=(255, 255, 0, 160))
            g.line((16 + x0, 32 + y0 + f * (y1 - y0), 16 + x1, 32 + y0 + f * (y1 - y0)), fill=(255, 255, 0, 160))
        g.rectangle((16 + sx - 1, 32 + sy - 1, 16 + sx + 1, 32 + sy + 1), outline=(255, 0, 255, 255))
        pics.append(grid)
        W = sum(p.width for p in pics) + 8 * len(pics)
        H = max(p.height for p in pics)
        tile = Image.new("RGBA", (W, H + 12), (25, 25, 25, 255))
        ImageDraw.Draw(tile).text((2, 0), f"{key} {how}", fill=(255, 255, 255, 255))
        x = 0
        for p in pics:
            tile.alpha_composite(p, (x, 12))
            x += p.width + 8
        tiles.append(tile.resize((tile.width * Z, tile.height * Z), Image.NEAREST))
    per = 12
    for n in range(0, len(tiles), per):
        chunk = tiles[n:n + per]
        cols = 3
        cw = max(t.width for t in chunk)
        rh = [max(t.height for t in chunk[i:i + cols]) for i in range(0, len(chunk), cols)]
        sheet = Image.new("RGBA", (cw * cols, sum(rh)), (10, 10, 10, 255))
        y = 0
        for r, i in enumerate(range(0, len(chunk), cols)):
            for j, t in enumerate(chunk[i:i + cols]):
                sheet.alpha_composite(t, (j * cw, y))
            y += rh[r]
        s = min(1.0, 2200 / sheet.width, 2400 / sheet.height)
        if s < 1:
            sheet = sheet.resize((int(sheet.width * s), int(sheet.height * s)), Image.NEAREST)
        sheet.save(out_dir / f"seats_{tag}_{n // per}.png")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--review", type=Path, default=None, help="also write contact sheets with the rider drawn on")
    args = ap.parse_args()
    index = json.loads((PMD / "index.json").read_text(encoding="utf-8"))["dex"] if (PMD / "index.json").is_file() else {}
    seats = {"pmd": {}, "hgss": {}}
    rows = {"pmd": [], "hgss": []}
    for key, entry in sorted(index.items(), key=lambda kv: (int(kv[0].split("-")[0]), kv[0])):
        if "mount" not in entry:
            continue
        cells = pmd_cells(key, entry["mount"])
        s = cells and seat_for("pmd", key, cells)
        if s:
            seats["pmd"][key] = s
            rows["pmd"].append((key, cells, s))
    for p in sorted(HGSS.glob("*-normal.png")):
        key = p.name[: -len("-normal.png")]
        base = int(key.split("-")[0])
        if base not in FLY_LEARNERS or (base in NO_FLIGHT) or key == "487":
            continue  # Pidgeot flies for one with no flying art (Config.FLY_MOUNT.noFlight)
        cells = hgss_cells(key)
        s = cells and seat_for("hgss", key, cells)
        if s:
            seats["hgss"][key] = s
            rows["hgss"].append((key, cells, s))
    lines = ["-- GENERATED by tools/generate_fly_seats.py: where the player sits on each Fly Mount",
             "-- (lib/fly_mount.lua), in the art's own px, per frame: { x1, y1, x2, y2, ... } -- PMD: the",
             "-- \"mount\" sheet's cells; HGSS: the left-facing walk frames A, B. Edit the tool's SEATS.",
             "return {"]
    for style in ("pmd", "hgss"):
        lines.append(f"  {style} = {{")
        for key, (frames, _how) in seats[style].items():
            k = f'["{key}"]' if "-" in key else f"[{int(key)}]"
            flat = ", ".join(f"{x:g}, {y:g}" for x, y in frames)
            lines.append(f"    {k} = {{ {flat} }},")
        lines.append("  },")
    lines.append("}")
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)}: {len(seats['pmd'])} PMD, {len(seats['hgss'])} HGSS seats")
    if args.review:
        args.review.mkdir(parents=True, exist_ok=True)
        for style in ("pmd", "hgss"):
            review(rows[style], args.review, style)
        print(f"review sheets in {args.review}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
