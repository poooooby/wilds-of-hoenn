# Wilds of Hoenn: developer guide

Everything here is for working on the mod. Players only need the [README](README.md).

## Setup

```sh
# Copy Wilds of Kanto Revival's overworld art (needs a sibling ../overworld-spawn-mod
# checkout). Not committed to this repo (.gitignore): a fresh clone needs this before
# anything draws a sprite.
python3 tools/copy_wilds_assets.py

# Bake the HGSS / PokeMMO 18-frame sheets from those raw grids. Forms come from
# tools/form_art_map.py: raw grids, the Gen 9 follower pack, and (EMERALD_FORM_ART) a
# sibling ../pokeemerald-expansion checkout -- e.g. Zygarde Complete.
python3 tools/generate_true_size_18frame.py --report   # inspect detected column roles first
python3 tools/generate_true_size_18frame.py

# Optional: bake the PMDCollab sheets, portraits and swim bands (needs ../SpriteCollab).
# Also bakes the optional "fly" sheets birds in the sky fly with: a real Hover-Anim.png, or the
# animation the flyer audit picked per species (FLY_SOURCE: FlapAround's wing beat, Attack,
# Special0, Hop; "Walk" = none, the runtime falls back to Walk). An animation with no shiny
# upstream is recoloured: from the species' own shiny Walk when the two Walk sheets line up,
# else from its HGSS normal/shiny colours (shift in Lab, keeping the PMD shading).
python3 tools/generate_pmd_sprites.py
python3 tools/validate_pmd_sprites.py

# Link this repo into a sibling ../gen1recomp checkout's mods/ (a real NTFS junction on Windows)
./scripts/bootstrap.sh
```

## Tests

```sh
# Standalone unit tests (plain Lua, no engine needed)
for f in tests/*_unit_test.lua; do lua "$f" || echo "FAIL: $f"; done

# Engine tests (luajit, from inside the gen1recomp checkout; ROM-free unless noted)
cd ../gen1recomp
luajit mods/wilds_of_hoenn/tests/engine_patch_probe_test.lua
luajit mods/wilds_of_hoenn/tests/modkit_boot_test.lua
luajit mods/wilds_of_hoenn/tests/classic_encounters_test.lua
luajit mods/wilds_of_hoenn/tests/forage_ndex_catalog_test.lua  # with national_dex_gen3 linked
luajit mods/wilds_of_hoenn/tests/shiny_chain_test.lua          # FireRed imported, national_dex_gen3 + modern_spawns linked
cd -
```

The in-game checklist is [docs/MANUAL_TEST.md](docs/MANUAL_TEST.md).

## Release

```sh
python3 tools/validate_option_labels.py     # option labels <= 14 chars
python3 tools/validate_release_version.py   # manifest / main.lua version agreement

# .modkitignore lists every repo-only file by exact path (modkit has no wildcards).
# Regenerate it after adding, renaming or deleting a test / tool / script / doc;
# the release build refuses to run while it is stale.
python3 tools/check_modkitignore.py --write

# Build both release ZIPs: -hgss (HGSS / PokeMMO art only) and -hgss-pmd (+ PMDCollab).
# Sprites are packed into atlas shards first (--no-atlas for per-file sheets;
# --variant hgss|pmd for one build; --no-pmd / --rebake-pmd for the PMD bake).
# Shards hold colour NUMBERS (greyscale): a normal + shiny pair is stored once, its
# real colours in <family>_pal.png, and lib/sprite_atlas.lua rebuilds the exact sheet
# on first use (~1 ms). About a third of the full-colour size; the validator proves
# every sheet byte-identical. `generate_sprite_atlases.py --rgba` = the old shards.
python3 scripts/build-mod.py            # -> dist/ (every build goes there)
python3 tools/validate_sprite_atlases.py
```

Keep [README.md](README.md) describing the mod as it is now (players read it); what
changed goes in [CHANGELOG.md](CHANGELOG.md).

## How it works

Gen1Recomp's Gen 3 engine (`src/core/game3/`) has no mod seam yet for a visible overworld
actor: `mod.world:spawnNpc` returns "not supported", `ow.entities` is a read-only snapshot,
the field renderer has no draw hook and collision has no mod hook
([RFC 0014](https://github.com/bryanthaboi/gen1recomp/blob/main/docs/rfcs/0014-mod-driven-actors-and-adopted-link-sessions.md)
proposes one). This mod ships ahead of that with the `engine_internals` permission.
`lib/engine_patch.lua` is the *only* file that touches engine internals, and documents why
each touch is needed. The core three:

- `FieldEffects.collectActors` draws our wild Pokémon with the player, NPCs and the follower.
- `Objects.blocks` makes a wild Pokémon solid to NPCs, trainer sight and other wild Pokémon,
  while letting the player step onto one (the battle starts once they stand on its tile).
- `Follower.update` carries our per-tick update on the engine's own follower tick.

The party menu's companion rows, the follower's A-button menu, portraits and reflections add
a few more (`PartyMenu.update` / `handleInput`, `FieldMoves.fromMenu`, `Field.interact`,
`Message.draw`, `FieldEffects.drawBehind`). Every touch point is probed (`EnginePatch.probe()`)
before it is patched, and `tests/engine_patch_probe_test.lua` runs the same probe against a
real engine checkout: if a Gen1Recomp update moves one, the mod switches itself off and logs
what changed instead of crashing. Wild encounters come from the engine's own rules
(`Encounters.rules().rollSweetScent`); nothing about wild generation is reimplemented.

Start reading at the header of `lib/engine_patch.lua`, then each module's header in `lib/`.
Tests mirror `lib/` one to one in `tests/`.

This mod is a sister project to [Wilds of Kanto Revival](https://github.com/poooooby/wilds-of-kanto-gen-3),
built from scratch for Gen 3's engine. It shares no runtime code or save data with it, only a
read-only copy of its overworld art.
