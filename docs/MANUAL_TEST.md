# Manual test checklist (v1)

Nothing below has been run yet -- this mod has not booted against a real
Ruby/Sapphire/Emerald session. Run through this on each of the three
games before calling v1 verified; the engine probe test and standalone
suite only prove the code is internally consistent, not that it looks and
feels right in game.

## Per-game basics

- [ ] Mod installs and enables cleanly; FireRed/LeafGreen boots are
      untouched (check the log for "not a Ruby/Sapphire/Emerald boot").
- [ ] Route 101/102 (Ruby/Sapphire/Emerald): visible land wild Pokemon
      stand/wander in grass; walking into one starts a battle with that
      exact species/level; a caught/beaten one is gone and a new one
      appears elsewhere within a few seconds.
- [ ] Route 104/106 water: visible water wild Pokemon stay on water, never
      wander onto the beach.
- [ ] Petalburg Woods / Granite Cave: indoor-style grass/cave spawns work
      the same as outdoor routes.
- [ ] Route 119 (Emerald) or any Good/Super Rod water: fishing still
      works and is unaffected by Classic Enc.
- [ ] Route 113 (Emerald ash grass): spawns and battles correctly.

## Special areas

- [ ] Altering Cave (Emerald): the game's own variant rotation still
      works; this mod's spawns reflect whichever variant is active.
- [ ] An Emerald outbreak: the outbreak species appears as a visible
      spawn where expected.
- [ ] Sootopolis City: no visible water spawns (the engine's own water
      block applies, not reimplemented here).
- [ ] Safari Zone: left fully vanilla in v1 -- confirm no visible spawns
      and no interference with the Safari step/ball mechanic.
- [ ] Battle Pike (Emerald) / Battle Pyramid (Emerald): no visible spawns
      (`EnginePatch.isSweetScentFacility` should skip these maps).
- [ ] A roamer (Latios/Latias): a roamer encounter still behaves like a
      roamer (flees between areas, etc.) when triggered via a visible
      spawn.

## Options

- [ ] Show Wild Mons off: no visible spawns anywhere; vanilla random
      encounters resume.
- [ ] Classic Enc off: step-based grass/water random encounters stop, but
      fishing and Rock Smash still work, and visible spawns stay active.
- [ ] Silhouette Off/Undiscovered/All: Undiscovered flips to normal color
      immediately after catching that species; All silhouettes every
      visible spawn regardless of Pokedex state.
- [ ] Shiny Rate Vanilla/Boosted/Off: Boosted should produce a visibly
      shiny wild Pokemon noticeably more often than Vanilla; a shiny wild
      Pokemon shows its shiny sheet and is the same shiny in battle.
- [ ] Follower on/off: the party lead follows in the overworld when on; a
      party-lead swap changes the follower's sprite within a tick or two.

## Stress / edge cases

- [ ] Holding a movement key into a wild Pokemon doesn't start the battle
      more than once.
- [ ] Fleeing/losing/winning/catching a wild Pokemon all remove it from
      the overworld and eventually get replaced.
- [ ] Map transitions despawn everything on the old map and spawn fresh
      on the new one (no leaked entities, no lingering actors drawn at
      the wrong coordinates).
- [ ] A Repel in effect stops new low-level visible wild Pokemon from
      spawning (same as it suppresses the vanilla roll) -- a wild Pokemon
      already standing there before the Repel was used still battles
      normally on contact, the same way an already-visible Wilds of
      Kanto Revival spawn does.
