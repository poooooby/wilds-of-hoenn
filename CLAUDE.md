# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A Lua mod for [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp), targeting its `game3`
engine (Ruby, Sapphire, Emerald -- layout `rse`). Mod id `wilds_of_hoenn`. The repo root **is**
the mod: `manifest.json`, `main.lua`, `options.lua` live at the top level alongside `lib/`,
`assets/`, `tests/`, `tools/`, `scripts/`, `docs/`.

Sister project to [Wilds of Kanto Revival](https://github.com/poooooby/wilds-of-kanto-gen-3)
(`poooooby/wilds-of-kanto-gen-3`, a sibling checkout at `../overworld-spawn-mod`), built from
scratch for Gen 3's different engine. Shares no runtime code or save data with it -- only a
read-only copy of its overworld art (`tools/copy_wilds_assets.py`).

## Commands

Copy Wilds of Kanto Revival's art (needs a sibling `../overworld-spawn-mod` checkout):
```sh
python3 tools/copy_wilds_assets.py
```

Link this repo into a sibling `../gen1recomp` checkout's `mods/` (needed for the two
engine-dependent tests below; set `GEN1RECOMP_ROOT` if it isn't a sibling directory):
```sh
./scripts/bootstrap.sh
```
> **Windows checkout quirk** (same one Wilds of Kanto Revival's CLAUDE.md notes): the `ln -sfn`
> link can land stale if files were added to this repo after an earlier link was created.
> `scripts/bootstrap.sh` checks for this and tells you to rerun it; GitHub Actions (Linux) is
> unaffected.

Run a single standalone unit test (plain Lua, no engine needed):
```sh
lua tests/<name>_unit_test.lua
```

Run the full standalone suite:
```sh
for f in tests/*_unit_test.lua; do lua "$f" || echo "FAIL: $f"; done
```

Run the two engine-dependent tests (need `scripts/bootstrap.sh` first; run from inside the
gen1recomp checkout, with luajit):
```sh
cd ../gen1recomp
luajit mods/wilds_of_hoenn/tests/engine_patch_probe_test.lua
luajit mods/wilds_of_hoenn/tests/modkit_boot_test.lua
```
Both are ROM-free. `modkit_boot_test.lua` boots this mod through gen1recomp's real
`src.mods.Loader` (the same `tests/modkit` SDK harness Wilds-style Gen1Recomp mods use for
ROM-free testing) by forcing `generation = 3` and `GameVersion.set("emerald"/"firered")`
directly, since `tests/modkit/fixtures.lua` itself only has Gen 1 fixture data. That proves
`main.lua` boots, `EnginePatch.install()` patches the REAL engine functions, and the real
`Runtime` event bus reaches `SpawnManager` -- but with no real ROM-extracted encounter cache
mounted, it correctly places zero spawns (see the test's own header). Real spawn placement is
covered by `tests/spawn_manager_unit_test.lua` (fully faked engine) and ultimately by
`docs/MANUAL_TEST.md` (a real ROM session).

Pre-release validation:
```sh
python3 tools/validate_option_labels.py     # option labels <= 14 chars
python3 tools/validate_release_version.py   # manifest/main.lua (/tag) version agreement
```

Build the release ZIP:
```sh
python3 scripts/build-mod.py   # -> dist/wilds-of-hoenn-v*.zip
```

## Architecture

- **`lib/engine_patch.lua` is the ONLY module that touches `src/core/game3` internals.**
  Gen 3 has no mod seam yet for a visible overworld actor (no `spawnNpc`, read-only
  `ow.entities`, no draw hook, no collision hook -- see its header for the full reasoning and
  `docs/rfcs/0014-...` in the engine repo). Everything else in this mod calls through
  `EnginePatch.*` wrappers rather than requiring engine modules directly, so every engine touch
  point lives in one file and is covered by `tests/engine_patch_probe_test.lua`.
  - `EnginePatch.TARGETS` are the three functions this mod wraps (reversibly, probed first):
    `FieldEffects.collectActors` (draw), `Objects.blocks` (collision/contact), `Follower.update`
    (per-tick piggyback).
  - `EnginePatch.READONLY` are functions/data this mod reads but never wraps: encounter tables
    and rolls, terrain classification, collision queries, species/national-dex conversion, the
    live trainer id, the Pokedex caught flag, `GameVersion.layout`.
  - `EnginePatch.probe()` checks every target+readonly entry resolves to a function before
    `install()` touches anything. A probe failure disables the whole mod (`main.lua` never calls
    `install()`), falling back to fully vanilla play.
  - `EnginePatch.install(hooks, log)` is idempotent and `uninstall()` reverses it exactly --
    every wrap is also `pcall`-guarded at the call site so a bug in this mod's code falls through
    to vanilla engine behaviour instead of corrupting the draw/collision/tick loop.

- **Boot gate**: `main.lua` calls `EnginePatch.isRse()` before anything else. FireRed/LeafGreen
  (`layout() == "frlg"`) get zero installation -- this mod targets RSE only, since FRLG has its
  own `encounter_rules` module and `Gen3Compat.gen3MapId`'s `FR_`-prefix map convention that this
  mod has never been exercised against.

- **Contact detection** (`lib/battle_trigger.lua`): `Objects.blocks(tx, ty, exceptLocalId,
  elevation)` is the single engine choke point for "is this cell occupied" -- it backs player
  movement, NPC movement, and trainer sight lines all at once. The player's OWN collision check
  is the only caller that passes `exceptLocalId == nil` (`collision.lua:1003`); every NPC/sight
  caller passes its own `localId`. `main.lua`'s `blocks` hook callback uses exactly that signal to
  start a battle only on the player's own bump, while still blocking NPCs/sight-lines from a wild
  Pokemon like any other solid object.

- **Spawn generation** (`lib/spawn_manager.lua`, `lib/encounter_source.lua`): wild Pokemon are
  generated with `Encounters.rules().rollSweetScent(mapId, terrain)` -- the engine's own "give me
  a full encounter right now, no step-rate gate" path, already carrying ability bias,
  Synchronize/Cute Charm, roamers and outbreaks. Eligible cells come from
  `Encounters.terrainAt(x, y)` (the ROM's own per-tile encounter classification), never a
  reimplemented terrain rule. See [[prefer_game_data_over_reimplemented_rules]] in the sibling
  Wilds of Kanto Revival project's memory -- the same principle applies here even harder, since
  this mod's whole risk profile is "don't let the visible layer drift from what the engine would
  really generate."

- **Sprite identity is always the NATIONAL dex number**, converted from the engine-internal
  species id via `EnginePatch.nationalFor`/`speciesForNational` (`pokemon.lua:281,293`) --
  Treecko's internal id (277) is not its national number (252). Never key art lookups by the
  internal id or by display name.

- **Rendering** (`lib/actor_renderer.lua`, `lib/sprite_source.lua`): Gen 3's field already draws
  true-color, so this mod draws plain `love.graphics` quads -- no DMG-palette machinery to thread
  through, unlike Gen 1Recomp's `src/render/SpriteRenderer.lua`. Both Sprite Style choices use the
  same 6-frame sheet layout (stand down/up/left, walk down/up/left; right mirrors left); frame
  WIDTH is the whole sheet's width and frame HEIGHT is the sheet's height / 6, read from the
  actual loaded image rather than assumed, since the two styles differ in exactly this: Poke
  Followers / GSC is always a plain 16x16 frame, while HGSS / PokeMMO ("True Size") is a different
  native size per species (Bulbasaur 24x24, Pikachu 18x18, not always square -- e.g. dex 252 is
  25x28). `ActorRenderer.anchorOffset(frameW, frameH)` centers a frame horizontally in the 16px
  tile and flushes its bottom edge (feet) to the tile's bottom, the same way Gen 3's own native OW
  sprites anchor a variable-size OAM shape (`ow_sprites.lua`'s `(16 - spr.width) / 2`, `16 -
  spr.height`) -- a bigger HGSS sprite extends upward from its feet rather than being squashed or
  mis-centered. Style is resolved once at spawn/follower-tick time (`Config.spriteStyle`) and
  re-applied live on an options change via `SpawnManager:refreshSpriteStyle()` and
  `FollowerAdapter`'s own lead/style tracking -- cheap, since a renderer's resolved path (and so
  its image/quad cache key) already depends on `style`.

- **Shiny** (`lib/shiny.lua`): the real check is the engine's own `Pokemon.isShiny`
  (`pokemon.lua:1397`), exposed via `EnginePatch.isShiny`, against the live save's trainer id.
  Boosted mode constructs a personality that is both shiny AND keeps the original nature/gender,
  via `Shiny.boostedPersonality` -- a direct construction (not a blind reroll against a 1/8192
  chance), using a pure-Lua 16-bit xor (`Shiny._xor16`) rather than LuaJIT's `bit` library, since
  standalone tests run under plain Lua.

- **Follower** (`lib/follower_adapter.lua`): uses the engine's existing public
  `world.follower.spawn` hook, no patching needed. Keeps `Follower.current().sprite` pointed at
  an `ActorRenderer` for the current party lead, rebuilt only when the lead species changes.

- **Tests** mirror `lib/` modules 1:1 by filename (`tests/<module>_unit_test.lua`). Each builds
  its own `V.require` shim and a fake `engine_patch` (or fake `src.core.game3.*` modules behind a
  monkeypatched `require`, for `engine_patch_unit_test.lua` and `main_boot_unit_test.lua`
  specifically) -- follow that pattern for new tests rather than introducing a shared framework.
  `tests/engine_patch_probe_test.lua` is the one test that needs a real `gen1recomp` checkout.

## What v1 deliberately leaves out

No Chase or Hidden behaviours, no Spawn Amount/density option (fixed curve in `lib/config.lua`),
no Sprite Fade, no Dive/underwater maps, no Safari Zone visible spawns (left fully vanilla), no
Battle Pike/Pyramid visible spawns (`EnginePatch.isSweetScentFacility` skips them outright). See
`README.md` for the full list and `docs/ARCHITECTURE.md` if it grows beyond this file.
