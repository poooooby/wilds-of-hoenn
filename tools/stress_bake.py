#!/usr/bin/env python3
"""Hardware stress test built from the sprite atlas bake -- the workload that crashed a
Ryzen 7800X3D twice when it ran one worker per hardware thread.

Not part of the build. It bakes the full atlas over and over with every hardware thread
(default) into its own scratch folder under %TEMP% (never the repo's assets/atlas), and
checks that every pass produces exactly the same bytes. The bake is deterministic, so a
pass whose output differs from the first one -- or from the known-good assets/atlas when
that exists -- means the machine computed something wrong: a silent CPU / memory error,
which is what an unstable overclock, undervolt or memory setting looks like before it
crashes outright.

  python3 tools/stress_bake.py                  # 30 minutes, all threads, index + rgba
  python3 tools/stress_bake.py --minutes 120 --jobs 16
  python3 tools/stress_bake.py --mode index     # only the default (crash) workload
  python3 tools/stress_bake.py --passes 1 --jobs 4   # quick check that it works

By default the bake runs at NORMAL priority, as it did when it crashed (the build itself now
runs below normal); --priority below keeps the build's gentler setting.

Needs the baked sprites (tools/copy_wilds_assets.py, tools/generate_true_size_18frame.py,
and the PMD bake from scripts/build-mod.py). Stop it any time with Ctrl+C.
"""
import argparse
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ATLAS_TOOL = ROOT / "tools" / "generate_sprite_atlases.py"
SCRATCH = Path(tempfile.gettempdir()) / "woh-stress-bake"


def digest(folder: Path) -> dict:
    """Relative path -> sha256 of every file under `folder`."""
    out = {}
    for p in sorted(folder.rglob("*")):
        if p.is_file():
            out[p.relative_to(folder).as_posix()] = hashlib.sha256(p.read_bytes()).hexdigest()
    return out


def compare(a: dict, b: dict) -> list:
    """Paths whose bytes differ (or exist on only one side)."""
    return sorted(k for k in set(a) | set(b) if a.get(k) != b.get(k))


def bake(mode: str, jobs: int, out: Path, priority: str) -> float:
    env = dict(os.environ, WOH_BUILD_PRIORITY="normal" if priority == "normal" else "below")
    cmd = [sys.executable, str(ATLAS_TOOL), "--jobs", str(jobs), "--out", str(out)]
    if mode == "rgba":
        cmd.append("--rgba")
    start = time.time()
    res = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"bake failed (exit {res.returncode}):\n{res.stdout[-2000:]}\n{res.stderr[-2000:]}")
    return time.time() - start


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--minutes", type=float, default=30, help="run time (default: %(default)s)")
    ap.add_argument("--passes", type=int, default=None, help="stop after this many passes instead")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4,
                    help="worker processes (default: every hardware thread, %(default)s)")
    ap.add_argument("--mode", choices=("both", "index", "rgba"), default="both",
                    help="index = the default colour-numbered bake (the crash workload), rgba = full colour")
    ap.add_argument("--priority", choices=("normal", "below"), default="normal",
                    help="normal = as when it crashed (default), below = the build's below-normal")
    args = ap.parse_args()

    modes = ["index", "rgba"] if args.mode == "both" else [args.mode]
    # the repo's own atlas (made by the release build) is the known-good index bake
    reference = {}
    real = ROOT / "assets" / "atlas"
    if "index" in modes and real.is_dir():
        reference["index"] = digest(real)
    SCRATCH.mkdir(parents=True, exist_ok=True)

    print(f"stress bake: {args.jobs} workers at {args.priority} priority, modes {', '.join(modes)}, "
          + (f"{args.passes} passes" if args.passes else f"{args.minutes:g} minutes"))
    print(f"scratch: {SCRATCH}")
    deadline = time.time() + args.minutes * 60
    passes = bad = 0
    try:
        while True:
            for mode in modes:
                out = SCRATCH / mode
                secs = bake(mode, args.jobs, out, args.priority)
                got = digest(out)
                passes += 1
                stamp = time.strftime("%H:%M:%S")
                if mode not in reference:
                    reference[mode] = got
                    print(f"[{stamp}] pass {passes:3d} {mode:5s} {secs:5.1f}s  {len(got)} files (reference)")
                    continue
                diff = compare(reference[mode], got)
                if diff:
                    bad += 1
                    print(f"[{stamp}] pass {passes:3d} {mode:5s} {secs:5.1f}s  MISMATCH in {len(diff)} files: "
                          + ", ".join(diff[:5]) + (" ..." if len(diff) > 5 else ""))
                else:
                    print(f"[{stamp}] pass {passes:3d} {mode:5s} {secs:5.1f}s  identical")
            if args.passes and passes >= args.passes:
                break
            if not args.passes and time.time() >= deadline:
                break
    except KeyboardInterrupt:
        print("stopped")
    finally:
        shutil.rmtree(SCRATCH, ignore_errors=True)
    print(f"done: {passes} passes, {bad} mismatched" + ("  <-- UNSTABLE" if bad else ""))
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
