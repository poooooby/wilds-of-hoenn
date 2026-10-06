# Wilds of Hoenn

Visible, reactive wild Pokemon for the Hoenn overworld -- **Ruby,
Sapphire and Emerald** -- on
[Gen1Recomp](https://github.com/bryanthaboi/gen1recomp)'s `game3` engine.
A sister project to [Wilds of Kanto
Revival](https://github.com/poooooby/wilds-of-kanto-gen-3), built from
scratch for Gen 3's very different engine internals; it shares no runtime
code or save data with it, only a read-only copy of its overworld art.

> **Status: v1, pre-release.** The engine has no mod seam for a visible
> overworld actor on Gen 3 yet (see "How this works" below), so this mod
> reaches into a handful of engine internals directly. Every one of those
> touch points is probed before anything is patched; if a future
> gen1recomp update moves one, this mod disables itself and logs exactly
> what changed instead of crashing or behaving unpredictably. In-game
> verification (see `docs/MANUAL_TEST.md`) has not happened yet.

## What it does

- Visible wild Pokemon stand and wander in grass and water, the same way
  Wilds of Kanto Revival does for Gen 1. Touch one and you battle **that
  exact Pokemon** -- its species, level, personality, IVs and roamer-ness
  all came from the real wild-generation rules
  (`Encounters.rules().rollSweetScent`), not a separate reimplementation.
- Ability bias (Magnet Pull / Static), Synchronize, Cute Charm,
  Ruby/Sapphire IVs, Emerald outbreaks, roamers and the Sootopolis water
  block all come from the engine's own rules -- nothing about wild
  generation itself is reimplemented.
- Idle and Roam behaviours (no Chase or Hidden in v1).
- Two Sprite Styles, same as Wilds of Kanto Revival: **Poke Followers /
  GSC** (plain 16x16) or **HGSS / PokeMMO** ("True Size" -- each species
  drawn at its own native size, anchored at its feet, so a Snorlax is
  genuinely bigger on screen than a Rattata). Switching takes effect
  immediately, including on already-spawned wild Pokemon.
- A real Gen 3 shiny check against your own trainer ID, with an optional
  Boosted rate that re-rolls a non-shiny encounter until it's shiny while
  keeping its nature and gender.
- A Silhouette option (Off / Undiscovered / All) and an optional party
  follower.
- A Classic Enc toggle for the original step-based random encounters;
  fishing and Rock Smash are never affected by it.

See `options.lua` for the exact option list and `CLAUDE.md`'s "What v1
deliberately leaves out" section for what's not here yet.

## How this works

Gen 1Recomp's Gen 3 engine (`src/core/game3/`) has no mod seam yet for a
visible overworld actor: `mod.world:spawnNpc` returns "not supported",
`ow.entities` is a read-only snapshot, the field renderer has no draw
hook, and collision has no mod hook
([RFC 0014](https://github.com/bryanthaboi/gen1recomp/blob/main/docs/rfcs/0014-mod-driven-actors-and-adopted-link-sessions.md)
proposes one but it isn't implemented). This mod ships ahead of that,
using the `engine_internals` permission to patch three functions directly
(`lib/engine_patch.lua` is the *only* file that does this, and documents
exactly why each one is needed):

- `FieldEffects.collectActors` -- draws our wild Pokemon alongside the
  player, NPCs and the follower.
- `Objects.blocks` -- makes a wild Pokemon solid, and is how a player's
  own bump is told apart from an NPC just walking past one (see
  `lib/battle_trigger.lua`'s header for exactly how).
- `Follower.update` -- piggybacks our own per-tick spawn/behaviour update
  onto the engine's existing follower tick, instead of needing a second
  hook into the field loop.

Every one of these is probed (`EnginePatch.probe()`) before it's touched.
`tests/engine_patch_probe_test.lua` runs that same probe against a real
engine checkout, so an update that moves one of these fields fails CI
loudly instead of quietly breaking spawns in the field.

The party follower itself needs no patching at all -- it uses the
engine's existing, public `world.follower.spawn` hook.

## Installation

1. Build or download the release ZIP (`manifest.json` at its root).
2. Import it via the Gen1Recomp Mod Manager, or place it in your mods
   directory.
3. Enable **Wilds of Hoenn**. It installs nothing on FireRed/LeafGreen.

## Development

```sh
# Copy Wilds of Kanto Revival's overworld art (run once, or after that
# repo updates its art); expects a sibling ../overworld-spawn-mod checkout
python3 tools/copy_wilds_assets.py

# Standalone unit tests (plain Lua, no engine needed)
for f in tests/*_unit_test.lua; do lua "$f" || echo "FAIL: $f"; done

# Link this repo into a sibling ../gen1recomp checkout's mods/
./scripts/bootstrap.sh

# Engine probe test + a ROM-free real-Loader boot test (both luajit, run
# from inside the gen1recomp checkout)
cd ../gen1recomp
luajit mods/wilds_of_hoenn/tests/engine_patch_probe_test.lua
luajit mods/wilds_of_hoenn/tests/modkit_boot_test.lua
cd -

# Pre-release validation
python3 tools/validate_option_labels.py
python3 tools/validate_release_version.py

# Build the release ZIP -> dist/wilds-of-hoenn-v*.zip
python3 scripts/build-mod.py
```

See `CLAUDE.md` for the full architecture and module-by-module notes.
