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

# Found the real root cause after chasing this as an "ln -sfn can go
# stale" quirk through two rounds of hardening: on this Windows/Git Bash
# setup, `ln -s` was never creating a symlink OR a junction at all -- it
# was silently falling back to a one-time RECURSIVE COPY (no error, no
# warning). Every "stale file" was really just "changed in the real repo
# since the last bootstrap.sh run" -- confirmed by comparing Explorer's
# reparse-point icon against other mods/ entries (national_dex_gen3,
# overworld_wild_spawns) that genuinely are Junctions, and by
# `Get-Item .. | Select LinkType,Attributes` showing plain `Directory`
# with no `ReparsePoint` for ours. A real Junction (same mechanism the
# other mods use, and what conf.lua's own comment on
# love.filesystem.setSymlinksEnabled calls out as "the mklink /J
# workflow on Windows") stays live with NO relink ever needed -- proven
# by editing a file in the real repo with no relink and reading the
# change straight back through the link.
#
# `ln -s` is kept for Linux/Mac (GitHub Actions, a real checkout) where
# it's a genuine symlink with no such fallback.
is_windows() {
  [ "${OS:-}" = "Windows_NT" ] || case "$(uname -s 2>/dev/null || true)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

relink() {
  rm -rf "$LINK"
  if is_windows && command -v powershell.exe >/dev/null 2>&1; then
    local winRoot winLink
    winRoot="$(cygpath -w "$ROOT" 2>/dev/null || echo "$ROOT")"
    winLink="$(cygpath -w "$LINK" 2>/dev/null || echo "$LINK")"
    powershell.exe -NoProfile -Command \
      "New-Item -ItemType Junction -Path '$winLink' -Target '$winRoot' | Out-Null" \
      || fail "New-Item -ItemType Junction failed -- create it by hand: mklink /J \"$winLink\" \"$winRoot\""
  else
    ln -s "$ROOT" "$LINK"
  fi
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
