#!/usr/bin/env bash
# Link this repo into a sibling gen1recomp checkout's mods/ directory, so
# the engine-dependent tests (tests/engine_patch_probe_test.lua,
# tests/modkit_boot_test.lua) can run with luajit the same way Wilds of
# Kanto Revival's own harness tests do.
#
# Does not clone gen1recomp itself -- point GEN1RECOMP_ROOT at an existing
# checkout (default: a sibling ../gen1recomp directory, matching this
# repo's own layout convention of living next to overworld-spawn-mod).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="${GEN1RECOMP_ROOT:-$ROOT/../gen1recomp}"

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ -f "$ROOT/manifest.json" ] || fail "missing manifest.json at repo root"
[ -d "$ENGINE" ] || fail "no gen1recomp checkout at $ENGINE (set GEN1RECOMP_ROOT)"
[ -f "$ENGINE/src/core/GameVersion.lua" ] || fail "$ENGINE doesn't look like a gen1recomp checkout"

LINK="$ENGINE/mods/wilds_of_hoenn"
mkdir -p "$ENGINE/mods"

# Windows checkout quirk (same one Wilds of Kanto Revival's CLAUDE.md
# notes, but worse than documented there): `ln -sfn` over an EXISTING
# link can land a junction that serves STALE CONTENT for a file that
# exists on both sides (not just omit a file added after the link was
# made) -- bit us for real, twice, on DIFFERENT files each time
# (options.lua once, lib/actor_renderer.lua another time) while OTHER
# files through the same link stayed fresh. Staleness is apparently
# per-file, not per-link, so checking only one file (the original
# options.lua-only check) can pass clean while another file is still
# stale -- this now diffs every git-tracked source file, not just one.
relink() {
  rm -rf "$LINK"
  ln -s "$ROOT" "$LINK"
}

stale_files() {
  local f
  while IFS= read -r f; do
    case "$f" in assets/*) continue ;; esac  # not committed, irrelevant here
    if ! diff -q "$ROOT/$f" "$LINK/$f" >/dev/null 2>&1; then
      echo "$f"
    fi
  done < <(cd "$ROOT" && git ls-files -- '*.lua' '*.json' manifest.json)
}

say "linking this repo into $LINK"
relink

STALE="$(stale_files || true)"
if [ -n "$STALE" ]; then
  say "link looks stale -- recreating ($(echo "$STALE" | wc -l) file(s) differed)"
  relink
  STALE="$(stale_files || true)"
fi
if [ -n "$STALE" ]; then
  fail "link still serves stale content after recreating -- remove $LINK by hand and re-run this script. Stale: $(echo "$STALE" | tr '\n' ' ')"
fi
[ -f "$LINK/tests/engine_patch_probe_test.lua" ] || fail "link created but the mod's own tests/ isn't visible through it -- rerun this script"

cat <<EOF

Bootstrap complete. From inside $ENGINE:
  luajit mods/wilds_of_hoenn/tests/engine_patch_probe_test.lua
  luajit mods/wilds_of_hoenn/tests/modkit_boot_test.lua

Both are ROM-free (the modkit SDK harness forces generation=3 and a Gen 3
GameVersion directly rather than needing a real ROM-extracted cache --
see modkit_boot_test.lua's header for exactly what that does and doesn't
prove).
EOF
