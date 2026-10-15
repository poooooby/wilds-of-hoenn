#!/bin/sh
# Plays the trailer reel: sh showcase/run.sh <emerald|firered> [first shot number | shot name]
# Needs this repo linked into a sibling ../gen1recomp checkout (scripts/bootstrap.sh) and
# the game's ROM imported. Your gen1recomp options.lua is backed up first and put back
# when the window closes (the reel changes Wilds' options in memory only).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${GEN1RECOMP_ROOT:-$HERE/../../gen1recomp}"
GAME="${1:-emerald}"
START="${2:-1}"
LOVE="${LOVE:-/c/Program Files/LOVE/lovec.exe}"
cd "$ROOT" || { echo "no gen1recomp checkout at $ROOT"; exit 9; }
BACKUP="${TMPDIR:-${TEMP:-/tmp}}/showcase_options_backup.lua"
cp options.lua "$BACKUP"
ONLY=""
case "$START" in ''|*[!0-9]*) ONLY="$START"; START=1 ;; esac
# POKEPORT_DRIVER_PACED: a driver run steps the game once per rendered frame and, by
# default, renders as fast as the display allows; paced, with the director's 60 fps cap,
# it runs at 1x on any display
env POKEPORT_VERSION="$GAME" POKEPORT_DRIVER="$HERE/director.lua" POKEPORT_DRIVER_PACED=1 SHOWCASE_DIR="$HERE" \
  SHOWCASE_START="$START" SHOWCASE_ONLY="$ONLY" "$LOVE" .
rc=$?
cp "$BACKUP" options.lua
echo "showcase exited ($rc); options.lua restored"
