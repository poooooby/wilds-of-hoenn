# Changelog

## Unreleased (v1)

Initial build. Not yet verified in game -- see `docs/MANUAL_TEST.md`.

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
- Overworld art is a read-only copy of Wilds of Kanto Revival's walker
  sheets (`tools/copy_wilds_assets.py`), covering national dex 1-386.

### Known gaps (tracked for a later version, see CLAUDE.md)

- No Chase or Hidden behaviours.
- No Spawn Amount / density option (fixed curve).
- No Dive/underwater map support.
- Safari Zone and Battle Pike/Pyramid are left fully vanilla (no visible
  spawns there).
