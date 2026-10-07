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
- Two Sprite Styles: **HGSS / PokeMMO** ("True Size" -- each species
  drawn at its own native size, anchored at its feet, so a Snorlax is
  genuinely bigger on screen than a Rattata) or **PMDCollab** (fully
  animated walking and idle loops; species without PMD art fall back to
  HGSS / PokeMMO). Switching takes effect immediately, including on
  already-spawned wild Pokemon.
- A real Gen 3 shiny check against your own trainer ID, with an optional
  Boosted rate that re-rolls a non-shiny encounter until it's shiny while
  keeping its nature and gender.
- A Silhouette option (Off / Undiscovered / All) and an optional party
  follower.
- A Classic Enc toggle for the original step-based random encounters;
  fishing and Rock Smash are never affected by it.
- Art covers national dex 1-1025 in both styles (not capped at Gen 3's
  native 386), so a National Dex expansion mod can hand this mod a
  species beyond Hoenn and it still draws correctly. Shipped as a baked
  sprite atlas (a handful of shard PNGs), not ~3900 individual files.

See `options.lua` for the exact option list and the "Known gaps" list in
`CHANGELOG.md` for what's not here yet.

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
- `Objects.blocks` -- makes a wild Pokemon solid to NPCs, trainer
  sight and other wild Pokemon, while letting the player step onto one:
  a battle starts only once the player is standing on its tile (see
  `lib/battle_trigger.lua`'s header).
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
# repo updates its art); expects a sibling ../overworld-spawn-mod checkout.
# Not committed to this repo (see .gitignore) -- a fresh clone needs this
# before anything will actually draw a sprite.
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

# Build the release ZIPs -> dist/wilds-of-hoenn-v*-hgss.zip (HGSS / PokeMMO
# art only) and -hgss-pmd.zip (+ PMDCollab). Default: bakes the sprite
# sheets into assets/atlas/ shards first and ships those instead of the
# per-file sheets; --no-atlas for the old layout, --variant hgss|pmd for one
python3 scripts/build-mod.py
```

## License

The mod's own code and tools are released under the [MIT License](LICENSE).
The sprite art it uses is NOT covered by it: HGSS / PokeMMO art comes from
Wilds of Kanto Revival's sources and the optional PMDCollab art is licensed
CC BY-NC 4.0 -- see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for each
asset's credit and terms.

For the architecture, start with the header comment of `lib/engine_patch.lua` (the only
file that touches engine internals) and then each module's own header in `lib/`.
