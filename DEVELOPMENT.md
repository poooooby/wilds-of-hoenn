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
# Special0, Hop; "Walk" = none, the runtime falls back to Walk), and the optional "hop" sheets
# the leaping fish play (HOP_SPECIES only: lib/water_life.lua), and the Local Scenes' "sleep" /
# "dance" / "rotate" sheets (SCENE_SPECIES only: Slakoth, Vigoroth, Silcoon / Cascoon,
# lib/local_scenes.lua; a one-row sheet like Sleep is repeated for every facing). An animation with no shiny
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
luajit mods/wilds_of_hoenn/tests/modkit_boot_test.lua           # Emerald, FireRed, LeafGreen, Red, Gold boots
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

### Red, Blue, Yellow, Gold, Silver, Crystal

Gen1Recomp runs the Game Boy games on two other engines (`src/world/OverworldController.lua`
for Gen 1, `src/world/gen2/World.lua` for Gen 2). On such a boot `lib/engine_patch.lua` hands
out `lib/engine_gb.lua` in its own place: the same API, answered for those engines
(`lib/gb/gen1.lua`, `lib/gb/gen2.lua` hold what differs), so `SpawnManager`, `BattleTrigger`,
`FollowerAdapter` and the renderers run unchanged. Its seams, probed and reversible like
`engine_patch`'s:

- `OverworldState.drawWorld` / `World.drawPeople`: for the length of that call, one proxy per
  actor we collect is appended to the list the engine y-sorts and draws (`ow.entities` /
  `world.npcs`), and removed afterwards. Our Pokémon sort with the player and NPCs and get the
  engine's grass over their feet; collision, NPC movement, trainer sight and talking never see
  them. Both engines draw a walker 4 px above its tile (`lib/gb_color.lua` FOOT_LIFT). While a
  render pipeline mod (3D: TERRARIUM, Potato Voxel, Dramaless; Stadium2 on Gen 2, through
  `World.drawPipeline`) draws the world, only renderer-drawn actors go in, each with the
  `pose()` the pipeline reads: a sheet baked from our own art in Gen 1's 6-frame layout
  (`lib/voxel_sheets.lua`, a composed `Assets` path; luminance shades outside true-colour modes)
  whose def carries its real `frameWidth` / `frameHeight` / `anchorX` / `anchorY`. The cards get
  that size from `lib/compat/`: Wilds of Kanto Revival's adapters, copied as they are (one
  file per provider over `voxel_sprite_billboards_adapter.lua`), but for a log shim and the
  feet `cut` TERRARIUM passes. The follower's sprite hands the pipeline the same kind of sheet.
- `OverworldState.update` / `World.step`: the per-tick update. `OverworldState.handleInput` /
  `World.pollInput`: a waiting contact holds the player.
- The public `movement.collision` hook (main.lua, `EngineGb.collisionVerdict`): a wild Pokémon
  blocks every mover but the player and the follower.
- The engine's own follower (`world.follower.spawn`; Red and Blue get a placeholder
  `SPRITE_PIKACHU` record at load) carries our renderer in an engine-shaped sprite
  (`EngineGb.followerSprite`); anything else a caller reads comes from its own engine sprite.

Encounters are the engines' own slot picks (Gen 1's buckets, Gen 2's `Encounter.grassSlot` by
time of day / `waterSlot`, Unown by unlocked letters) on the engines' own encounter tiles; Gen
2 rolls the DVs at spawn time, so shininess shows and the battle (`Mon.new`, `World:startBattle`)
is that Pokémon. Gen 1 battles go through `BattleState.newWild` + `pushBattle`, the way a step
encounter does (ghosts, Safari). Colour: Gen 1's palette-zone pass re-colours the world canvas,
so outside its true-colour modes our art is drawn through a 3-shade luminance shader
(`lib/gb_color.lua`). Not built on these boots (`Config.gbBoot`, `EngineGb.supports`): the sky,
Water Life, Local Scenes, Wild Reacts, the companion roles and menus, Sweet Scent, reflections.

To try it in a real game with Wilds of Kanto Revival installed, switch that off for the game
first: the loader drops the mod that declares the conflict, which is this one.

Start reading at the header of `lib/engine_patch.lua` (and `lib/engine_gb.lua`), then each
module's header in `lib/`.
Tests mirror `lib/` one to one in `tests/`.

This mod is a sister project to [Wilds of Kanto Revival](https://github.com/poooooby/wilds-of-kanto-gen-3),
built from scratch for Gen 3's engine and since grown to cover Gen 1 and 2 too (use one or the
other). It shares no runtime code or save data with it, only a read-only copy of its overworld
art.
