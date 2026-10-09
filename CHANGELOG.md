# Changelog

## 1.6.1 (2026-10-09)

### Added

- A Battler that levels up now asks you to finish the job. It cannot learn moves or
  evolve mid-walk, so "New move ready!" and "Ready to evolve!" float over its head
  (alternating when both apply) until you face it, press A and pick **Learn Move**
  or **Evolve** from the menu, which opens the game's own move relearner (listing
  only the moves it skipped) or evolution scene (you can stop it). Remembered per
  Pokemon in the save; it stops asking when the move is known or the evolution is
  no longer possible. It is kept per Pokemon in the save, so it survives a battle,
  leaving the area, recalling the Pokemon, swapping it out, the PC and a reload,
  and a request to evolve stays until the Pokemon evolves. A Pokemon holding an
  Everstone never asks to evolve (the request returns if the stone comes off), and
  while a move or evolution is waiting the Battler earns no more EXP, so no level
  (and no move) is skipped.

## 1.6.0 (2026-10-08)

### Added

- Alternate forms draw their own art. With National Dex Gen 3 installed, a form in
  your party or a wild spawn (Wormadam-Sandy, Rotom-Heat, Galarian / Hisuian forms,
  Flabebe colours ...) is looked up by its form (`%03d-<form>`, e.g. `479-heat`)
  instead of its base species' dex number. PMDCollab has 68 form sheets and 64
  form portraits (a form without its own portrait shows its base species') and HGSS has 73 (from the Wilds grids and the Gen 9
  follower pack). A form with no art of its own draws its base species: Pumpkaboo /
  Gourgeist sizes, Zygarde Complete, Antique Sinistea / Polteageist, Artisan
  Poltchageist, Masterpiece Sinistcha (no different sprite exists for them), and a few
  PMD forms. See `tools/form_art_map.py`.

## 1.5.0 (2026-10-08)

### Fixes

- A shiny Pokemon's follower is now shiny too (it was always drawn in normal
  colours). It uses the same real shiny check as the overworld spawns, on the
  Pokemon's own personality and trainer ids, and rebuilds when you swap to or
  from a shiny.

## 1.4.0 (2026-10-08)

### New

- Talk to your Pokemon (face it, press A) and the menu is now Interact
  (Pet / Play / Talk), Role (Follow / Forage / Fight) and Recall, each sub menu
  with a Back row (B goes back too). Recall shrinks it back into you;
  it stays inside until you pick a job for it again, from this menu or from the
  party menu's ROLE row.
- The party menu now has a single ROLE row (with a right arrow) that opens a sub
  menu: Follow / Forage / Fight / Back (B goes back too). It replaces the three
  Follow / Battle / Forage rows, and always fits the box, so the one-row
  COMPANION fallback is gone.
- Changing the companion (another Pokemon, another job, or a recall) is now a
  scene: after you close the menu, you raise a Poke Ball in one hand, the old
  companion shrinks into you, then you raise it again and the new one grows
  out and cries. (`lib/follower_swap.lua`, `Config.SWAP`)

### Fixes

- The "+EXP" / "Found X!" label is no longer cut off on Android (and other
  window scalings): it is drawn once into a tiny canvas and drawn like a
  sprite, instead of being clipped with a scissor rectangle.
- The same label was also cut off on FireRed / LeafGreen (its text was drawn
  too high for that game's small font); it now sits inside its box on both.
- The follower's grass: a big follower is drawn away from its own tile, so the
  grass tuft over that tile cut across its body. The grass now goes on the grass
  tiles under its real feet, snapped to the tile grid. A companion inside the
  player has no grass.

## 1.3.0 (2026-10-07)

### Fixes

- PMDCollab: fixed walking sprites flicking to their Idle pose between steps
  (Treecko) and Grovyle looking like it was floating. The game reports
  "not moving" for a tick or two between chained steps, which dropped the
  sprite to Idle and restarted its walk; the Walk animation now keeps playing
  for a few ticks after movement stops (`Config.PMD_WALK_LINGER`).

## 1.2.2 (2026-10-07)

### Changes

- PMDCollab art update: 20 more species now have PMD sprites (997 of 1025;
  the rest still fall back to HGSS / PokeMMO), including 18 hand-added ones
  credited in `THIRD_PARTY_NOTICES.md`. Seven species (Vileplume, Machamp,
  Hitmonchan, Jynx, Exploud, Walrein, Aegislash) gained their full set of 16
  portrait emotions.
- `assets/pmd/CREDITS.txt` now also credits the portrait artists, and the
  hand-added sprites' artists.
- (HGSS Only build: no change from 1.2.1.)

## 1.2.1 (2026-10-07)

### Changes

- The Forager now heads out every 5-15 seconds of walking (was every 1-2.5 s).
- The Forager only cries when it actually finds something; a dig that turns
  up nothing is silent.

### Features

- Follower interactions fleshed out: **Play** +3, **Pet** +2, **Talk** +1
  friendship. A Pokemon that is hurt (under 25% HP) or has a status
  condition **refuses to play** and says why ("is sick and can't play").
  **Pet** has a 25% chance to cure a status condition ("feels better
  now!"). **Talk** reports how fond of you it is as a share of maximum
  friendship (wary, curious, starting to like you, trusts you, really likes
  you, loves you) with a matching portrait.

## 1.2.0 (2026-10-07)

### Features

- **Companion roles** (Scarlet / Violet style). Open the party menu, pick ANY
  party Pokemon and choose **Follow**, **Battle** or **Forage**: it becomes
  the one out in the overworld with that job. The **Follower** option is
  gone (a companion is always out; the party lead follows until you choose).
  - **Battle**: it stays near you and, when everything is still, charges
    any wild overworld Pokemon within 3 tiles of you for a short fight using
    its REAL moves, stats, damage and PP, with health bars over both, a hit
    effect and attack / hurt animations (PMD: the species' own Attack and
    Hurt sheets; HGSS: a rapid idle). A defeated wild Pokemon cries and sinks
    into the ground; the Battler earns a small share of the EXP. It is never
    knocked out: at 1 HP (or out of attacks) it runs back, cries and shrinks
    into you and stays inside until it is healed.
  - **Forage**: while you are walking, outside on a route or in a cave (never
    in a building, town, city, the Safari Zone or on the water), it roams 5-10
    tiles around you on open ground and runs back to your side; every 10-30
    seconds of walking it goes foraging: it cries to alert you, digs, has a 20%
    chance to turn up an item for your bag ("Found Potion!"), then runs back
    quickly. The timer carries across map changes. Finds: healing and status items, Poke
    Balls, berries, evolution stones and the extra evolution items National
    Dex Gen 3 adds, cheap TMs. Never HMs, key items, Master Balls, Rare
    Candy or high-level TMs.
- The PMDCollab build bakes two more animations per species (Attack, Hurt).

## 1.1.1 (2026-10-07)

### Fixes

- HGSS / PokeMMO sprites now draw in a release ZIP. Their sheets ship only
  inside the sprite atlas there, and the art lookup only looked for loose
  files, so switching to the HGSS style (and the whole HGSS Only build, and
  PMD builds' ~48 species without PMD art) drew nothing.

## 1.1.0 (2026-10-06)

### Features

- Follower interaction scenes: **Play** has you throw a ball (the engine's
  arms-up pose) that the follower runs to, spins around and brings back;
  **Pet** plays a quick Idle then its cry; **Talk** plays its cry three times.
  Each runs before the result message and portrait, with the field locked.
  Works in both Sprite Styles; tuned through `Config.ACTIONS`.

## 1.0.1 (2026-10-06)

### Fixes

- PMDCollab: large sprites are no longer scaled up (the baked true-size
  scale is ignored; `Config.PMD_TRUE_SIZE` turns it back on).
- PMDCollab follower: tighter spacing while walking down (tall sprites like
  Rayquaza trailed too far above the player).
- PMDCollab follower: the offset slides at a capped speed when the player
  changes direction, so large sprites glide instead of snapping.

## 1.0.0 (2026-10-06)

Two builds per release: **HGSS Only** (small, for low-power devices) and
**HGSS + PMDCollab** (animated walk/idle, portraits, follower
interaction; its art is CC BY-NC, non-commercial only).

Visible wild Pokemon and the party follower have been confirmed working
in a real game session. FireRed / LeafGreen support, the surf recall and
the rest of `docs/MANUAL_TEST.md` are not yet play-tested.

### Features

- Visible wild Pokemon in grass and water for Ruby, Sapphire and Emerald,
  generated via the engine's own `rollSweetScent` (ability bias,
  Synchronize/Cute Charm, roamers, Emerald outbreaks, Ruby/Sapphire IVs
  all included; nothing about wild generation is reimplemented).
- Modern Spawns integration (soft, no dependency): when the `modern_spawns`
  mod is installed and active, each visible spawn takes the species Modern
  Spawns generated for the slot the engine rolled (plus its LEGENDARIES
  roll). Level, personality and the rest of the engine's roll are kept.
  See `lib/modern_spawns_bridge.lua`.
- Idle flap: floating/flying species (those in the baked `levitates` pack, used as a species reference only -- never drawn) slowly play their walk frames while standing still, for wild spawns and the party follower.
- Water art (swimming/levitates) is baked shrunk to match each species' land size (`tools/generate_true_size_18frame.py`, same perceived-size idea as Wilds of Kanto Revival). Re-run the generator with `--kind swimming,levitates --force` after a fresh asset copy.
- PMDCollab Sprite Style (third option): fully animated Walk and Idle loops from SpriteCollab, timed by each species' AnimData.xml frame durations, for wild spawns and the party follower. Baked by `tools/generate_pmd_sprites.py` (needs a sibling `../SpriteCollab` checkout; output `assets/pmd/` is gitignored and packed into the release atlas). Species without PMD art fall back to HGSS / PokeMMO. See `THIRD_PARTY_NOTICES.md` for the licence (CC BY-NC).
- Portrait system (`lib/portrait_ui.lua`): a 40x40 PMDCollab portrait (all 16 standard emotions; a species missing one falls back along a chain ending at Normal) whose face follows the Pokemon's real state (`lib/mon_mood.lua`: fainted / critical HP / status condition / low HP / friendship tier) drawn above the left of the dialogue box while a message is open, via a new `Message.draw` hook in `lib/engine_patch.lua`. Baked by `tools/generate_pmd_sprites.py` into `assets/pmd/portraits/` + `portraits.json` (1025 species, shiny sheets where SpriteCollab has them). Exposed as `mod.exports.portraitUI` (`say`, `show`, `setEmotion`, `clear`); the follower interaction menu is the first user.
- Follower interaction: face your follower and press A. It tells you how it is (portrait + words from its real HP, status and friendship), then offers Pet / Play / Talk / Cancel. Pet uses the engine's own massage friendship event; Play and Talk give a small flat gain. Rate-limited (`Config.INTERACT`): per-action cooldowns, a budget per 10 minutes, and an escalating lock-out (5 min, doubling to 1 h) for button-mashing; the state lives in `mod.storage` so reloading a save or rewinding does not reset it, and a set-back clock does not skip a cooldown.
- Reachable-only spawns (`lib/reachability.lua`): wild Pokemon appear only where the player can actually get to from where they stand -- a flood fill built on the engine's own `Collision.canEnter` (walls, elevation, one-way ledge hops), so sealed cave chambers, fenced-off ground and waterways cut off from the player never spawn anything. Water counts only once Surf is usable (or while surfing); Cut trees, smashable rocks and boulders block until their move is usable; NPCs and item balls do not. Re-measured on map entry, when the player ends up outside the area, and every 15 s (so learning Surf or cutting a tree opens new ground). `Config.REACHABLE_SPAWNS` turns it off.
- `scripts/build-mod.py` now bakes PMDCollab itself: when a SpriteCollab checkout is found (`$SPRITECOLLAB`, else `../SpriteCollab`) it runs `tools/generate_pmd_sprites.py` (only missing sheets; `--rebake-pmd` rewrites all, `--no-pmd` skips), then packs the Walk, Idle and portrait sheets into the release atlas (`pmd_walk`, `pmd_idle`, `pmd_portraits`) and fails the build if an atlas family is missing. 977 species (every Gen 1-3 species included); the 9 that ship an Idle animation but no Walk (Stunfisk, Aromatisse, Toucannon, Dachsbun, Grafaiai, Iron Treads, Ting-Lu, Gouging Fire, Raging Bolt) use their Idle frames, capped at 10 ticks each, as the walk loop. The remaining 48 have no sprite folder upstream and keep the HGSS / PokeMMO art.
- Poke Followers / GSC and the Pokewilds extension are removed (Kanto-only): `tools/copy_wilds_assets.py` no longer copies them, the atlas has no `poke_followers` family, the release has none of their art, and the Sprite Style option is HGSS / PokeMMO or PMDCollab. A saved "Poke Followers / GSC" setting falls back to the new default, PMDCollab (species without PMD art use HGSS / PokeMMO).
- Shiny portraits are no longer baked (a shiny Pokemon talks with its normal face): about half of the portrait art and ~12 MB off the release. `--shiny-portraits` on `tools/generate_pmd_sprites.py` brings them back.
- Fixed: walking straight through a wild Pokemon (holding a direction, e.g. in a cave) did not start a battle -- only stopping on it did. Contact is now the engine's `world.stepped` event, so arriving on its tile always counts.
- Two release builds from one command (`python3 scripts/build-mod.py`, or `--variant hgss|pmd`): `wilds-of-hoenn-v<ver>-hgss.zip` (HGSS / PokeMMO art only) and `wilds-of-hoenn-v<ver>-hgss-pmd.zip` (HGSS / PokeMMO + PMDCollab). Same code and mod id; the mod hides the PMDCollab Sprite Style, and defaults to HGSS / PokeMMO, when no PMD art is installed (`Config.hasPmdArt`). Only the `-pmd` build carries the CC BY-NC PMDCollab art.
- PMDCollab follower while surfing: PMD has no swim art, so the follower shrinks into the player like a Poke Ball recall and grows back out once it is on land (`Config.PMD_RECALL_TICKS`, `PMD_RECALL_LIFT`). It stays in until the follower itself is off the water, and cannot be talked to while inside. HGSS / PokeMMO still uses its swim art.
- FireRed and LeafGreen are supported alongside Ruby, Sapphire and Emerald: the boot gate accepts both Gen 3 layouts (`EnginePatch.layoutName()`), FRLG spawns roll the personality the FRLG encounter rules leave out (so the sprite's shiny/gender is the Pokemon you fight), and Safari Zone maps (both families) spawn nothing so the engine's own Safari battles are untouched. Verified against the real engine's FireRed and LeafGreen boots; not yet play-tested in game.
- Idle and Roam behaviours.
- Contact with a visible wild Pokemon starts a battle with that exact
  mon (species, level, personality, IVs, roamer-ness).
- Gen 3 shiny check against the live trainer id, with an optional
  Boosted re-roll that keeps nature and gender (SHINY RATE option).
- Silhouette option (Off / Undiscovered / All).
- Optional party follower, via the engine's public `world.follower.spawn`
  hook.
- Classic Enc toggle for the original step-based random encounters
  (fishing and Rock Smash are unaffected either way).
- Sprite Style option: HGSS / PokeMMO or PMDCollab (Wilds of Kanto's Poke
  Followers / GSC style is Kanto-only and not part of this mod). HGSS /
  PokeMMO is "True Size" -- each species drawn at its own native frame
  size, anchored at its feet, the same way Gen 3's own native overworld
  sprites anchor a variable-size OAM shape to a 16px cell). Switching
  takes effect immediately on already-spawned wild Pokemon and the
  follower, not just new ones.
- Overworld art is a read-only copy of Wilds of Kanto Revival's sprite
  sheets (`tools/copy_wilds_assets.py`), both styles, covering national
  dex 1-1025 -- not capped at Gen 3's native 386, since a National Dex
  expansion mod (`national_dex_gen3`) can put later species in a real
  save. Shipped as a baked atlas, not 1000+ individual files (see
  "Sprite atlas" below).
- Sprite atlas (`lib/sprite_atlas.lua`, `tools/generate_sprite_atlases.py`,
  default in `scripts/build-mod.py`): packs the ~3900 per-species sheets
  into a handful of shard PNGs + JSON indexes at release time, served
  under their original paths. A repo checkout (or `--no-atlas` build)
  keeps the real per-file sheets and never touches the atlas; it exists
  purely so the release ZIP and the GitHub history don't carry thousands
  of individual PNGs.

### Known gaps (tracked for a later version)

- No Chase or Hidden behaviours.
- No Spawn Amount / density option (fixed curve).
- No Dive/underwater map support.
- Safari Zone and Battle Pike/Pyramid are left fully vanilla (no visible
  spawns there).
