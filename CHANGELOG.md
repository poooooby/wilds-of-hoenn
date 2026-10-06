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
- Sprite Style option: Poke Followers / GSC (plain 16x16) or HGSS /
  PokeMMO ("True Size" -- each species drawn at its own native frame
  size, anchored at its feet, the same way Gen 3's own native overworld
  sprites anchor a variable-size OAM shape to a 16px cell). Switching
  takes effect immediately on already-spawned wild Pokemon and the
  follower, not just new ones.
- Overworld art is a read-only copy of Wilds of Kanto Revival's sprite
  sheets (`tools/copy_wilds_assets.py`), both styles, covering national
  dex 1-386.

### Known gaps (tracked for a later version, see CLAUDE.md)

- No Chase or Hidden behaviours.
- No Spawn Amount / density option (fixed curve).
- No Dive/underwater map support.
- Safari Zone and Battle Pike/Pyramid are left fully vanilla (no visible
  spawns there).
