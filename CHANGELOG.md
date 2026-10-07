# Changelog

## Unreleased (v1)

Visible wild Pokemon and the party follower have been confirmed working
in a real game session. The rest of `docs/MANUAL_TEST.md` is still
outstanding.

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
