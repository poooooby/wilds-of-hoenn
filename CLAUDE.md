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
read-only copy of its overworld art (`tools/copy_wilds_assets.py`), covering national dex
1-1025 in both Sprite Styles (not capped at Gen 3's native 386 -- see lib/sprite_source.lua).
That art is NOT committed to this repo (`.gitignore`); a fresh clone needs
`tools/copy_wilds_assets.py` before anything draws a sprite, and the release ZIP ships a baked
atlas instead of the ~3900 individual files (`lib/sprite_atlas.lua`).

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
> **Windows note:** on at least one real Windows/Git Bash setup, plain `ln -s` silently fell back
> to a one-time recursive COPY instead of a real link or junction -- no error, just permanently
> stale content the moment anything in this repo changed. `scripts/bootstrap.sh` detects Windows
> and creates a real NTFS Junction via PowerShell instead (`New-Item -ItemType Junction`, the same
> mechanism gen1recomp's other `mods/*` dev links use) -- confirmed live with no relink needed
> after editing a file through the real repo. GitHub Actions (Linux) still uses plain `ln -s`,
> which is a genuine symlink there.

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

Build the release ZIP (bakes the sprite atlas by default; `--no-atlas` = old per-file layout):
```sh
python3 scripts/build-mod.py   # -> dist/wilds-of-hoenn-v*.zip
```

Rebuild just the sprite atlas (also run automatically by `scripts/build-mod.py`):
```sh
python3 tools/generate_sprite_atlases.py
python3 tools/validate_sprite_atlases.py   # proves the bake is lossless and complete
```

Rebake the 18-frame True Size walker sheets from raw source grids (needs
`tools/copy_wilds_assets.py` first; see "Sprite source pipeline" below):
```sh
python3 tools/generate_true_size_18frame.py --report   # inspect detected column roles first
python3 tools/generate_true_size_18frame.py             # bake everything
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
    and rolls, terrain classification, collision queries (`canEnter`, `isWater`, `isGrass`),
    species/national-dex conversion, the live trainer id, the Pokedex caught flag,
    `GameVersion.layout`, the grass field-effect sheet loader (`grassSheet`), and the player's own
    `running` data field. One entry, `playerRunning` (`player.lua:62`), is NOT a function -- it has
    `kind = "data"`, the one deliberate exception `probe()` special-cases (checks "resolves to
    something non-nil" instead of "resolves to a function").
  - `EnginePatch.probe()` checks every target+readonly entry resolves to a function (or, for a
    `kind = "data"` entry, to any non-nil value) before `install()` touches anything. A probe
    failure disables the whole mod (`main.lua` never calls `install()`), falling back to fully
    vanilla play.
  - `EnginePatch.canEnter(game, tx, ty, opts)` sets a reentrancy flag
    (`EnginePatch.isProbingCanEnter()`) around its call into the engine -- see "Contact detection"
    below for why this exists (a real bug it fixes, not defensive paranoia).
  - `EnginePatch.install(hooks, log)` is idempotent and `uninstall()` reverses it exactly --
    every wrap is also `pcall`-guarded at the call site so a bug in this mod's code falls through
    to vanilla engine behaviour instead of corrupting the draw/collision/tick loop.

- **Boot gate**: `main.lua` calls `EnginePatch.isRse()` before anything else. FireRed/LeafGreen
  (`layout() == "frlg"`) get zero installation -- this mod targets RSE only, since FRLG has its
  own `encounter_rules` module and `Gen3Compat.gen3MapId`'s `FR_`-prefix map convention that this
  mod has never been exercised against.

- **Contact detection** -- a battle starts ONLY when the player arrives on the wild Pokemon's tile, never from an adjacent bump: the `blocks` hook answers `false` for the player's own check (so they can step onto it) and the engine's `world.stepped` event (emitted inside `Player`'s `finishStep`, the same moment the engine rolls its own wild encounters) calls `BattleTrigger:onPlayerStepped(x, y)`. That event, not a "standing still" check, is the real signal: holding a direction starts the next step in the SAME `Player.update` that finished the last one, so the player is never at rest on a tile they walk through (the cave bug: mons could be walked straight through but battled when you stopped on them). `BattleTrigger:checkContact` (from `followerTick`, only when `EnginePatch.playerCell()` says `moving == false`) stays as the backstop for a player resting on one. `SpawnManager:_cellFree` keeps spawns off the player's cell and the cell they are stepping into. The rest of this paragraph describes why the nil-`exceptLocalId` guard exists. (`lib/battle_trigger.lua`, `main.lua`'s `blocks` hook): `Objects.blocks(tx,
  ty, exceptLocalId, elevation)` is the single engine choke point for "is this cell occupied" -- it
  backs player movement, NPC movement, and trainer sight lines all at once. The player's OWN
  collision check passes `exceptLocalId == nil` (`collision.lua:1003`) -- **but so does OUR OWN
  roaming wild Pokemon's candidate-step check** (`lib/behavior.lua`'s `canStep` ->
  `EnginePatch.canEnter` -> the real `Collision.canEnter`, which ALWAYS resolves occupancy through
  `entityBlocks()` -> `Objects.blocks(tx, ty, nil, elevation)`, unconditionally nil regardless of
  caller -- confirmed directly in the engine source, not assumed). Without a guard, a roaming
  Pokemon merely CONSIDERING a step onto the player's own tile -- needing no player movement at
  all -- would start a battle on its own (a real bug: a standing-still player got thrown into
  battle this way). `EnginePatch.canEnter` sets a reentrancy flag
  (`EnginePatch.isProbingCanEnter()`) around its call into the engine; the `blocks` hook checks it
  and skips the battle trigger for our own internal probe while still answering "occupied"
  correctly (so a wild Pokemon still won't actually path onto the player). `lib/behavior.lua`'s
  `canStep` also checks `terrainAt` BEFORE calling `canEnter` at all, so a direction that could
  never be legal terrain for that Pokemon never reaches the engine's collision system in the first
  place -- belt and suspenders, not strictly required for correctness once the flag exists, but
  avoids a pointless reentrant engine call.

- **Spawn generation** (`lib/spawn_manager.lua`, `lib/encounter_source.lua`): wild Pokemon are
  generated with `Encounters.rules().rollSweetScent(mapId, terrain)` -- the engine's own "give me
  a full encounter right now, no step-rate gate" path, already carrying ability bias,
  Synchronize/Cute Charm, roamers and outbreaks. Eligible cells come from
  `Encounters.terrainAt(x, y)` (the ROM's own per-tile encounter classification), never a
  reimplemented terrain rule. See [[prefer_game_data_over_reimplemented_rules]] in the sibling
  Wilds of Kanto Revival project's memory -- the same principle applies here even harder, since
  this mod's whole risk profile is "don't let the visible layer drift from what the engine would
  really generate."

- **Modern Spawns** (`lib/modern_spawns_bridge.lua`, sibling repo `../g1r_modern_spawns`): `rollSweetScent` calls the
  engine's rules directly, so Modern Spawns' `encounter.*` hooks never see visible spawns. The bridge reads its
  `mod.exports` (`drawFor`, `legendaryFor`, `profileOf`; `apiVersion >= 1`, `generation() == 3`) and swaps only the
  species of the slot the engine rolled (matched by species + level against `EnginePatch.tableFor`; slot order is
  the same), converting its string id to an internal id via the profile's dex number. Soft: absent/inactive/erroring
  -> the engine's own encounter. Roamers are never touched.

- **Sprite identity is always the NATIONAL dex number**, converted from the engine-internal
  species id via `EnginePatch.nationalFor`/`speciesForNational` (`pokemon.lua:281,293`) --
  Treecko's internal id (277) is not its national number (252). Never key art lookups by the
  internal id or by display name.

- **Rendering** (`lib/actor_renderer.lua`, `lib/sprite_source.lua`): Gen 3's field already draws
  true-color, so this mod draws plain `love.graphics` quads -- no DMG-palette machinery to thread
  through, unlike Gen 1Recomp's `src/render/SpriteRenderer.lua`. Frame WIDTH is always the whole
  sheet's width and frame HEIGHT is the sheet's height / frameCount, read from the actual loaded
  image rather than assumed (frames stack in a single vertical strip). One layout:
  Wilds of Kanto's Poke Followers / GSC style (6-frame, 16x16) is Kanto-only and was removed
  from this mod -- `ActorRenderer.frameCountFor` is always 18, and a stale saved `"followers"`
  option falls back to the default style (`Config.VALID_SPRITE_STYLE` is `pokemmo`, `pmd`;
  default `pmd`). `STYLE_POKEMMO` (HGSS / PokeMMO, "True Size"): **18 frames**, matching the real Gen 3 player
    NPC's own animation layout (`sapphire/data/generated/gba/ow/manifest.lua` graphics id 0,
    decoded via `src/core/game3/ow_sprites.lua`'s STAND/WALK_A/WALK_B/RUN_BASE/RUN_A/RUN_B
    tables) -- stand x3, walk-A/walk-B x3 directions (a real 2-phase alternating cycle, not a
    single static walk pose), run-base/run-A/run-B x3 directions. A different native size per
    species (Bulbasaur 24x24, Pikachu 18x18, not always square -- dex 252 is 25x28).

  `ActorRenderer.POSE_STAND/WALK_A/WALK_B/RUN_BASE/RUN_A/RUN_B` is the pose enum the caller
  computes and passes as `draw()`'s `walkPhase` argument (NOT a binary flag) -- `frameIndexFor`
  decodes it per `(facing, pose, frameCount)` against the single 18-frame table.
  This mod can **never** rely on the engine's own `stepFlip` draw() parameter for A/B
  alternation: `field_view.lua:569` hardcodes `stepFlip = false` for every actor that isn't the
  player itself, so A/B phase is tracked and carried entirely through `walkPhase` by whoever owns
  the entity -- `lib/behavior.lua` toggles `entity.stepParity` once per NEW step (not per tick)
  for wild Pokemon; `lib/follower_adapter.lua` does the same by watching the follower npc's own
  `moving` transitions, since it doesn't own the follower's movement, only observes it.

  `ActorRenderer.anchorOffset(frameW, frameH)` centers a frame horizontally in the 16px tile and
  flushes its bottom edge (feet) to the tile's bottom, the same way Gen 3's own native OW sprites
  anchor a variable-size OAM shape (`ow_sprites.lua`'s `(16 - spr.width) / 2`, `16 - spr.height`).
  Style is resolved once at spawn/follower-tick time (`Config.spriteStyle`) and re-applied live on
  an options change via `SpawnManager:refreshSpriteStyle()` (which ALSO re-derives `frameCount` --
  it does not just flip `style` and leave the old frame layout stale) and `FollowerAdapter`'s own
  lead/style tracking.

  **Presentation** (land vs water art, `SpriteSource.PRESENTATION_LAND/SWIMMING/LEVITATES`):
  a second, independent dimension from `style`. It resolves into
  `assets/wilds_generated/true_size18/{hgss,swimming,levitates}/` (land's baked folder is named
  `hgss`, NOT `land` -- a real bug once, watch for it), falling through swimming -> levitates ->
  land if the specific water pack doesn't cover a dex (narrower coverage than land is expected;
  confirmed directly against Kanto's own `water_sprite_registry.lua` that "try swimming, then
  levitates" IS the real behaviour, not a simplification -- its per-species
  `preferredWaterKind` override field is unset on every real entry). `lib/spawn_manager.lua`
  resolves presentation from `entity.terrain`; `lib/follower_adapter.lua` resolves it each tick
  from `EnginePatch.isWater(npc.cellX, npc.cellY)`.

  **Running** (follower only -- wild Pokemon never run): `lib/follower_adapter.lua` reads
  `EnginePatch.playerIsRunning()` (`player.lua:62`'s `Player.running` -- a live DATA FIELD, not a
  function; `EnginePatch.probe()` has a `kind = "data"` entry type specifically for this one
  exception) and picks RUN_A/RUN_B by the same step-parity tracking used for walking.

  **Large-follower spacing** (`ActorRenderer.behindOffset`/`largePushback`,
  `ActorRenderer:frameWidth()`): a True Size follower sprite wider than one tile gets pushed back
  along its own facing direction at DRAW TIME ONLY -- the single-follower analog of Wilds of Kanto
  Revival's multi-trailer convoy spacing (`ControlEngine`'s `_largeTrailerPushbackPx`), adapted
  because this mod does NOT own the follower's movement (the engine's `Follower.lua` does):
  nudging `npc.px/py`/`cellX/cellY` would get baked into the engine's own `fromX`/`targetX` step
  bookkeeping and compound every subsequent step, so the offset lives entirely inside
  `ActorRenderer:draw()`, never touching position state. `lib/follower_adapter.lua` recomputes it
  every tick from `(frameWidth - 16) / 2`, a no-op for any species whose
  art fits in one tile.

- **"Sinking into grass"** (`lib/grass_cover.lua`): the engine's own field effects draw a static
  grass-tuft overlay over any REGISTERED NPC's feet when it's standing in grass
  (`field_effects.lua`'s "Grass feet cover for NPCs" block, looping `Objects.forDraw()`) -- but
  neither our wild Pokemon nor the follower are registered engine NPCs, so neither was ever picked
  up by it. `lib/grass_cover.lua` reimplements that exact per-entity geometry/visibility check
  (same `Collision.isGrass` + feet-in-band test) for entities the engine doesn't know about, using
  the SAME sprite data the engine itself uses (`EnginePatch.grassSheet()` ->
  `FieldEffects.loadSheet("tall_grass", 16, 16, 5)`, a public engine loader, memoized by the
  engine itself -- not reimplemented art). Deliberately does NOT replicate the player's own
  ANIMATED rustle (`FieldEffects._fx`) -- that is a genuine engine singleton keyed to one tile at
  a time, and triggering it for a wild Pokemon or the follower would stomp the player's own
  rustle state; this matches how the actual games treat NPCs too (only the player gets the
  animated rustle). Wired into `collectActors` from both `lib/spawn_manager.lua` (one overlay per
  live wild Pokemon) and `lib/follower_adapter.lua:collectActors` (the follower's own cell) --
  the follower's own actor entry is pushed separately, directly by the engine
  (`src/world/game3/Follower.lua`'s `actor()`, called by `field_view.lua` BEFORE our wrapped
  `collectActors` runs), so this module only ever adds the extra overlay, never the sprite itself.

- **Sprite source pipeline, raw art to baked sheet**: `tools/copy_wilds_assets.py` copies
  READ-ONLY art from the sibling Kanto checkout -- only the raw, un-baked 4x4-grid source grids
  (Kanto's Poke Followers / Pokewilds sheets and its old 6-frame `true_size/hgss` bake are
  deliberately NOT copied: Kanto-only / superseded by the 18-frame bake):
  (`assets/enhanced_overworld/followsprites/` for land,
  `assets/enhanced_overworld/water_sprites/{swimming,levitates}/{normal,shiny}/` for water -- one
  PNG per species+form+variant, rows = directions, columns = pose candidates).
  `tools/generate_true_size_18frame.py` (lives in and runs from THIS repo, unlike the finished
  sheets it doesn't exist in Kanto) bakes those raw grids into the 18-frame
  `assets/wilds_generated/true_size18/{hgss,swimming,levitates}/` sheets consumed above --
  column 0 is always stand; columns 1-3 are auto-detected per species+direction via pairwise
  pixel-difference (the two most SIMILAR columns become the walk-A/walk-B pair, the "odd one out"
  becomes run-base; there is no dedicated running art, so run-A/run-B reuse walk-B/walk-A's
  pixels) -- NOT a fixed column index, since nothing guarantees uniform column meaning across
  ~1000+ species (confirmed: a few real anomalies exist, e.g. Charizard's "up" row auto-detected
  the WRONG pair until a `MANUAL_OVERRIDES` entry pinned it -- see the script's own table, keyed
  by `(kind, dex)` since different kinds/presentations are independent source art with their own
  column layouts and must never share one override). `--report` mode prints detected roles
  without writing, for spot-checking before trusting a bake broadly.

- **Idle flap**: `SpriteSource.isFloater(mod, dex)` treats membership in the baked `true_size18/levitates` pack as "hovers/flies" (reference only, art is never drawn from it); idle floaters cycle `ActorRenderer.idleFlapPose` (walkA, stand, walkB, stand every `Config.IDLE_FLAP_TICKS`) in `SpawnManager` and `FollowerAdapter`.

- **PMDCollab style** (`lib/pmd_renderer.lua`, `lib/renderer_factory.lua`, `tools/generate_pmd_sprites.py`,
  `tools/validate_pmd_sprites.py`): a third Sprite Style, `"pmd"`. The bake reads a sibling `../SpriteCollab` checkout
  (`sprite/<dex4>/AnimData.xml`, `Walk-Anim.png`, `Idle-Anim.png`, `*-Shadow.png`) and writes `assets/pmd/{walk,idle}/
  <dex3>-<normal|shiny>.png` plus `assets/pmd/index.json` (cell size, frame count, per-frame 60Hz tick `durations`,
  ground anchor `ax/ay`) and `CREDITS.txt`. Sheet layout: columns = frames, rows = down/right/up/left (PMD's own
  8-row order Down, DownRight, Right, UpRight, Up, UpLeft, Left, DownLeft, rows 0/2/4/6 kept -- no mirroring), one
  shared crop window per animation plus a 2px transparent gutter, no resampling. Availability comes from
  `index.json` alone (`SpriteSource.pmdInfo`), so it is right in an atlas build; the per-file sheets are packed
  into the atlas families `pmd_walk` / `pmd_idle`. `RendererFactory.new` is the only place that chooses a renderer
  class: PMD when the species is in the index, else the `SpriteSource.PMD_FALLBACK_STYLE` ActorRenderer.
  `SpawnManager:tick` / `FollowerAdapter:tick` call `renderer:advance(moving)` (Walk while moving, Idle while
  standing, restart on switch); the idle-flap and follower pushback/glide logic apply to the ActorRenderer styles
  only. Tuning knobs: `Config.PMD_SCALE`, `PMD_GROUND_Y` (where the ground point sits in the 16px tile),
  `PMD_WALK_SPEED`. Surf recall: PMD has no swim art, so `FollowerAdapter:_tickRecall` drives `renderer.recall` (1 = out, 0 = inside the player) -- toward 0 while `EnginePatch.playerSurfState()` says surfing (and not dismounting), back to 1 once the player is on land AND the follower itself is off the water (`wasRecalled` keeps it in while it still trails over water tiles). `PmdRenderer:draw` blends its tile toward the player's pixel position (`recallBlend`, smoothstep, lifted `PMD_RECALL_LIFT` px), scales by the same factor and tints it red-white; at recall <= 0.02 it draws nothing. A fresh sprite starts in the right state (no shrink on map entry). `FollowerAdapter:isRecalled()` blocks the follower interaction menu while inside. Only the PMD renderer does this; HGSS / PokeMMO keeps its swim art. Coverage: every species SpriteCollab has Walk art for (977 of 1025, all of Gen 1-3); a species whose AnimData has an Idle but no Walk (`walkFromIdle` in the index) uses its Idle frames as the walk loop, each held at most `WALK_FROM_IDLE_MAX_TICKS` (10); the other 48 have no sprite folder upstream and fall back to HGSS. `<CopyOf>` anims (Idle copying Walk for Beedrill, Dragonair, Silcoon, Cascoon, Lileep ...) read the TARGET's sheet (`source` in `parse_anims`). Build: `scripts/build-mod.py` bakes PMD from a local SpriteCollab (`$SPRITECOLLAB` or `../SpriteCollab`) before the atlas step, so a plain `python3 scripts/build-mod.py` yields the full release ZIP (~60 MB); `--no-pmd` / `--rebake-pmd`. Two release variants by default (`--variant hgss|pmd|both`): `-hgss` (atlas families `hgss18,swimming18,levitates18` only, `assets/pmd/` excluded) and `-hgss-pmd` (everything); same code, same mod id, a player installs one. The mod adapts to what is installed: `Config.hasPmdArt(mod)` (= `assets/pmd/index.json` exists) makes `defineOptions` drop the PMDCollab Sprite Style choice (default HGSS / PokeMMO) and makes `Config.spriteStyle` return `pokemmo` for a saved `pmd`. True size: the bake stores a per-species `scale` in `index.json` (HGSS true-size height /
  PMD height, UP ONLY, quarter steps 1.25..2, else exactly 1 -- PMD art is never downscaled); the renderer draws
  at `PMD_SCALE * scale`. The follower is spaced out behind the player (`PMD_FOLLOWER_GAP` + the sprite's overhang
  past the 16px tile, eased on turns) and rests `PMD_FOLLOWER_IDLE_DELAY` ticks (300 = 5 s) on Idle's first frame after
  stopping, then plays Idle at `PMD_FOLLOWER_IDLE_SPEED` (0.5); wild Pokemon play Idle at `PMD_WILD_IDLE_SPEED` (0.75). Walking steps alternate A-step / B-step, each ending on a Base frame (`PmdRenderer.stepStart`). Licence: CC BY-NC -- see `THIRD_PARTY_NOTICES.md`.

- **Portraits** (`lib/portrait_ui.lua`, `EnginePatch.TARGETS.messageDraw`): the baked sheets are one per species
  (`assets/pmd/portraits/<dex3>-<normal|shiny>.png`, 40x40 cells side by side, columns = the emotions listed for the
  species in `assets/pmd/portraits.json`, which lives OUTSIDE `portraits/` because that directory is atlas-packed
  and left out of an atlas-mode ZIP). `PortraitUI` is an instance per mod (`mod.exports.portraitUI`): `say(text,
  {dex, shiny, emotion, stay, done})` opens an engine message (`EnginePatch.showMessage`) and the `messageDraw`
  wrap -- which runs after every `Message.draw()` -- paints the portrait above the dialogue frame
  (`Chrome.dialogueWindow()` via `EnginePatch.dialogueWindow`, nudge with `Config.PORTRAIT_X/Y`). The portrait
  clears itself the moment no message is open, so it can never get stuck on screen. A species/emotion without art
  falls back to Normal; one with no portraits draws nothing.

- **Mood** (`lib/mon_mood.lua`, pure): `MonMood.emotionFor(mon)` maps a party mon's state to a portrait emotion,
  highest priority first: fainted -> Teary-Eyed; HP <= 10% -> Crying; a status -> Pain (poison/toxic), Shouting
  (burn), Stunned (paralysis/freeze), Dizzy (sleep); HP <= 25% -> Pain; < 50% -> Worried; then the friendship tier
  of a healthy mon: <30 Angry, <70 Sad, <130 Normal, <200 Happy, <255 Joyous, 255 Inspired (a Joyous/Inspired mon
  that is even slightly hurt shows Happy). Status is read from the engine's string form ("PSN"/"TOX"/"BRN"/...),
  the GBA bitfield and the separate `sleep` counter. Determined and Surprised are never derived -- callers pass them
  as explicit moods for actions. `PortraitUI:showMon(mon, emotionOverride)` / `say(text, {mon = ...})` use it,
  `refreshMon(mon)` re-derives the face after the state changes. The bake keeps all 16 standard emotions per
  species; shiny portrait sheets are NOT baked by default (`portraits.json` `shiny=false`, so `portraitCell` serves the normal sheet; `--shiny-portraits` restores them); `SpriteSource.portraitCell` walks `EMOTION_FALLBACK` (e.g. Teary-Eyed -> Crying -> Sad -> Normal) for a
  species that lacks one.

- **Follower interaction** (`lib/follower_interaction.lua`, `lib/interaction_limiter.lua`, `lib/follower_dialogue.lua`;
  engine side: `EnginePatch.TARGETS.interact`): the follower is NOT an Objects entity and is passable, so the engine's
  A-button handler (`Field.interact`) never sees it. The `interact` hook runs BEFORE the original and returns true
  (press consumed) only when `canStartInteraction()` (field running/unlocked, no message/menu/fade/battle/script, player
  standing still) and `followerInFacingCell()` hold -- the player has to TURN toward it (a tap) and press A. Flow, as a
  per-tick state machine (`tick` runs from the follower tick; a stay message cannot say when its text finished and the
  choice callback fires inside the HUD's input handling): `report` (stay message with the lead mon's portrait, face and
  words from `MonMood.read`) -> `menu` (`Choice.multi` Pet/Play/Talk/Cancel, opened once `messageOnLastPage()`) ->
  `result` (normal message, closing it ends the interaction); `abort()` is the escape hatch whenever the screen is not
  in the state the current step expects. Happiness: Pet = `Pokemon.adjustFriendship(mon, FRIENDSHIP_EVENT_MASSAGE)`
  (tier-aware, Soothe Bell etc. apply), Play/Talk = flat `Config.INTERACT.gain`. A maxed (255) mon gains nothing and
  spends no budget. Anti-abuse (`Config.INTERACT`, real seconds): per-action cooldown, `maxGains` per rolling `window`,
  and EVERY selection (refused ones too) counts toward `abuseAttempts` in `abuseWindow` -> lock `lockBase`, doubling per
  repeat offence up to `lockMax`, strikes forgotten after `strikeReset`; locked = no menu, just a turned back. The clock
  is monotonic (set back = time stalls) and the state is saved through `mod.storage` (not rewound by checkpoints, unlike
  `mod.save`), falling back to `mod.save`; re-read on save.loaded/created and checkpoint.restored.

- **Reachable-only spawns** (`lib/reachability.lua`, `EnginePatch.reachMover`/`reachStart`/`canEnterWhy`/`hmUsable`,
  `EncounterSource:setReachable`, `SpawnManager:_rebuildReach/_checkReach/_pruneUnreachable`): a BFS flood fill from the
  player's cell over the engine's real movement rules, so no terrain rule is reimplemented. `reachMover` is the `move`
  function the pure BFS calls per step: `Collision.ledgeLanding` (a ledge is a one-way hop to its landing cell, so the
  set is "reachable FROM here", not "connected to"), else `Collision.canEnter` with `fromX/fromY/dir/surfing/elevation`
  exactly as `Player.beginStep` calls it, `Collision.nextElevation` carried along each path. Water: a `"water"`
  refusal from a walking cell is retried as surfing when `hmUsable("SURF")`; a surfer's step onto land is a dismount.
  An `"entity"` refusal (an NPC / item ball in the way) is treated as OPEN -- only after checking the terrain under it
  is passable, and NOT for Cut tree / Rock Smash rock / pushable boulder objects (`Objects.at` + `FieldMoves.GFX_IDS`)
  whose move the player cannot use yet. It goes through `EnginePatch.canEnterWhy`, which sets the same
  `_probingCanEnter` flag as `EnginePatch.canEnter` -- without it our own `blocks` hook would read the flood fill as
  the player bumping a wild Pokemon and start a battle. `hmUsable` = badge (`FieldMoves.hasBadge`) AND a party mon
  that knows it (`partyMoveUser`), failing OPEN on anything unreadable. `EncounterSource:setReachable(set)` is a view
  over the cells `loadMap` found; no engine support / no start cell -> no restriction (never an empty map). The set is
  rebuilt at map entry, whenever the stationary player is outside it (warp/ledge), and every
  `Config.REACH_REBUILD_TICKS` (Surf learned, a tree cut); a rebuild also despawns wild Pokemon left unreachable.
  Known approximation: one elevation per cell (the first found), so a cell reachable both over and under a bridge is
  judged by whichever path got there first.

- **Sprite atlas** (`lib/sprite_atlas.lua`, `tools/generate_sprite_atlases.py`,
  `tools/validate_sprite_atlases.py`, default in `scripts/build-mod.py`; `--no-atlas` builds
  per-file): bakes the per-species sheets into a few single-column shard PNGs + JSON indexes
  (`assets/atlas/`, gitignored build output) so the release ZIP and git history never carry one
  file per sprite. Families: `hgss18`/`swimming18`/`levitates18` (the 18-frame land/water bakes) and
  `pmd_walk`/`pmd_idle`/`pmd_portraits` (PMDCollab). Unlike
  Wilds of Kanto Revival's own `lib/sprite_atlas.lua`, this one does NOT wrap the shared engine
  `src.render.Assets` module -- this mod is the only consumer of these sprite paths
  (`ActorRenderer` draws its own quads, never through `SpriteRenderer`/`OwSprites`), so there is
  no shared choke point worth patching, and no `engine_internals` reach needed for this piece at
  all. `lib/actor_renderer.lua`'s `loadImage` tries the real per-file path first (a repo checkout
  always has it) and only falls back to `SpriteAtlas.image` when that fails. `lib/json_decode.lua`
  (copied from Wilds verbatim, no engine dependency) parses the index; one column per shard
  matters for the same deflate-window reason documented in Wilds' own generator (a wide
  shelf-packed atlas measured 33-67% larger there).

- **Shiny** (`lib/shiny.lua`, SHINY RATE option): the real check is always the engine's own
  `Pokemon.isShiny` (`pokemon.lua:1397`), exposed via `EnginePatch.isShiny`, against the live
  save's trainer id -- an encounter the engine's own roll already marked shiny is NEVER overridden
  to false by any rate tier; every tier below only ADDS a chance on top of it. Tiers: `native`
  (default, no reroll -- whatever the engine's own roll decided), `r4096`/`r2048`/`r1024`/`r500`/
  `r100`/`r10` (reroll a non-shiny encounter at that chance), `all` (always shiny, no roll). A hit
  on any tier (or `all`, unconditionally) constructs a personality that is both genuinely shiny
  AND keeps the original nature/gender via `Shiny.boostedPersonality` -- a direct construction
  (not a blind reroll against the engine's native 1/8192 chance, which would need ~8192 average
  tries), using a pure-Lua 16-bit xor (`Shiny._xor16`) rather than LuaJIT's `bit` library, since
  standalone tests run under plain Lua. Matches Wilds of Kanto Revival's SHINY RATE tiering (no
  "Off" choice here, unlike Kanto's -- a deliberate scope decision for this mod).

- **Follower** (`lib/follower_adapter.lua`): uses the engine's existing public
  `world.follower.spawn` hook, no patching needed. Keeps `Follower.current().sprite` pointed at an
  `ActorRenderer` for the current party lead, rebuilt when the lead species OR Sprite Style
  changes (not every tick); every tick also refreshes that renderer's pose (`poseOverride`,
  walk/run A-B by its own step-parity tracking), `presentation` (land/swimming/levitates by
  current cell), and `largePushback` (see "Rendering"'s Large-follower spacing above) -- these are
  cheap field writes on an already-built renderer, not a rebuild. Also appends the follower's
  "sinking into grass" overlay each frame via `collectActors` (see "Sinking into grass" above).

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
