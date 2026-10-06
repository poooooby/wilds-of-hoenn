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

say "linking this repo into $ENGINE/mods/wilds_of_hoenn"
mkdir -p "$ENGINE/mods"
ln -sfn "$ROOT" "$ENGINE/mods/wilds_of_hoenn"

# Windows checkout quirk (same one Wilds of Kanto Revival's CLAUDE.md
# notes): `ln -sfn` can land a junction that doesn't reflect files added
# to the target AFTER the link was created, until it's recreated. If a
# test can't find a file that genuinely exists in this repo, re-run this
# script.
if [ ! -f "$ENGINE/mods/wilds_of_hoenn/tests/engine_patch_probe_test.lua" ]; then
  fail "link created but the mod's own tests/ isn't visible through it -- rerun this script"
fi

cat <<EOF

Bootstrap complete. From inside $ENGINE:
  luajit mods/wilds_of_hoenn/tests/engine_patch_probe_test.lua
  luajit mods/wilds_of_hoenn/tests/modkit_boot_test.lua

Both are ROM-free (the modkit SDK harness forces generation=3 and a Gen 3
GameVersion directly rather than needing a real ROM-extracted cache --
see modkit_boot_test.lua's header for exactly what that does and doesn't
prove).
EOF
