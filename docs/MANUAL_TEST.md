# Manual test checklist (v1)

Confirmed in a real session so far: basic visible spawns and the party
follower both work. Everything else below is still unconfirmed -- the
engine probe test and standalone suite only prove the code is internally
consistent, not that it looks and feels right in game. Run through the
rest on each of the three games before calling v1 verified.

## Per-game basics

- [ ] Mod installs and enables cleanly on Ruby, Sapphire, Emerald, FireRed
      and LeafGreen (a non-Gen-3 boot logs "not a Gen 3 boot" and installs
      nothing).
- [x] Route 101/102 (Ruby/Sapphire/Emerald): visible land wild Pokemon
      stand/wander in grass; walking into one starts a battle with that
      exact species/level; a caught/beaten one is gone and a new one
      appears elsewhere within a few seconds. (confirmed basic spawning;
      the "same species/level/exact mon" and "replaced within a few
      seconds" details haven't been specifically checked yet)
- [ ] Wild Pokemon never wander off their patch onto a path, doodad, or
      any other non-encounter tile (fixed in lib/behavior.lua: roaming
      used to only check "not water", not "still a real encounter tile",
      so a land spawn could drift anywhere walkable -- confirmed by
      screenshot, a Pokemon standing on a dirt path outside the grass).
      Re-check this specifically; also confirm a battle never starts
      while standing outside the encounter area (that was very likely
      this same bug: bumping a Pokemon that had wandered onto the path).
- [ ] Contact: walking up beside a wild Pokemon (even one facing you) starts
      NO battle; stepping onto its tile does -- **including walking straight
      through it with the direction held** (caves), not only stopping on it.
      A spawn never appears under you.
- [ ] Route 104/106 water: visible water wild Pokemon stay on water, never
      wander onto the beach.
- [ ] Petalburg Woods / Granite Cave: indoor-style grass/cave spawns work
      the same as outdoor routes.
- [ ] Route 119 (Emerald) or any Good/Super Rod water: fishing still
      works and is unaffected by Classic Enc.
- [ ] Route 113 (Emerald ash grass): spawns and battles correctly.

## PMDCollab style (needs `python3 tools/generate_pmd_sprites.py` first)

- [ ] Options -> Sprite Style -> PMDCollab: wild Pokemon and the follower
      switch live (no respawn needed).
- [ ] Standing Pokemon play their Idle loop, walking ones the Walk loop, in
      all four directions; the loops are smooth (no snapping at the loop
      point, no bleed from neighbouring frames).
- [ ] Feet sit on the tile (tune `Config.PMD_GROUND_Y`), size reads right
      next to the player and NPCs (tune `Config.PMD_SCALE`), the walk cycle
      matches the step speed (tune `Config.PMD_WALK_SPEED`).
- [ ] True size: species PMD draws small next to their real size (e.g. Zubat
      line, dex 961/804/156 at 1.5x) look larger; nothing is ever smaller than
      its PMD art; big species still read big.
- [ ] Follower: kept clear of the player (tune `PMD_FOLLOWER_GAP`), glides
      (not snaps) when you turn, and waits `PMD_FOLLOWER_IDLE_DELAY` ticks
      after stopping before its Idle loop starts.
- [ ] Shiny spawns use the shiny sheet; silhouette options still work.
- [ ] A species with no PMD art (e.g. Pecharunt, dex 1025) falls back to
      HGSS / PokeMMO instead of vanishing.
- [ ] Grass cover still overlays the lower part of a PMD sprite in grass.
- [ ] Water spawns look acceptable (PMD has no water art; v1 reuses Walk/Idle).

## Portraits (needs `python3 tools/generate_pmd_sprites.py` first)

Nothing in the game opens a portrait message until the follower interaction
menu lands (phase 3); until then it can be exercised from a Lua console /
script with `mod.exports.portraitUI:say("Hello!", { dex = 252, emotion = "Happy" })`.

- [ ] The portrait sits above the left of the dialogue box, fully on screen,
      not overlapping the text (nudge with `Config.PORTRAIT_X/Y`).
- [ ] It disappears as soon as the message closes (A/B), never lingers.
- [ ] Emotions change the face (`setEmotion`); a species/emotion without art
      falls back to Normal; a shiny mon uses the shiny sheet.
- [ ] The face matches the mon's state: full HP + max friendship = Inspired,
      low friendship = Angry/Sad, poisoned = Pain, burned = Shouting,
      paralysed/frozen = Stunned, asleep = Dizzy, under 50% HP = Worried,
      under 25% = Pain, under 10% = Crying (try via
      `portraitUI:say("...", { mon = <party mon> })`).
- [ ] Ordinary NPC/sign messages (no portrait set) look exactly as before.

## Follower interaction

- [ ] Tap the direction toward your follower (so you turn to face it without
      stepping onto it) and press A: a message with its portrait describes its
      state, then a Pet / Play / Talk / Cancel menu opens under it.
      **Check this first:** the follower is passable, so a held direction walks
      you onto it; if turning in place toward it is not possible in practice,
      the interact test needs to accept an adjacent follower too.
- [ ] Pet / Play / Talk each reply with a matching face and raise happiness
      (check the summary screen: Pet ~+3, Play +2, Talk +1; Pet at 255 gives
      nothing). B and Cancel close everything with no portrait left behind.
- [ ] A poisoned / burned / low-HP lead keeps its pained face and gets the
      gentler replies.
- [ ] Repeating an action right away: "isn't in the mood". More than six
      successful interactions in 10 minutes: "has had enough attention".
- [ ] Mashing the menu (six picks inside 45 s) cuts it off: the Pokemon turns
      its back, A on it then shows only "wants some space" with no menu, the
      lock lasts ~5 minutes and doubles each repeat offence.
- [ ] Reloading the save / using a save state does NOT reset the lock or
      cooldowns; setting the system clock back does not either.
- [ ] Walking, NPC dialogue and signs behave exactly as before.

## Reachable-only spawns

The log prints one line per map: `reachable area on <map>: N cells (X ms)` --
check that the time stays small on the biggest routes (it runs on map entry and
every 15 s).

- [ ] No wild Pokemon on ground you cannot reach: behind a fence/ledge you
      cannot climb, in a cave chamber you cannot walk into, on an island, or on
      the far side of water before you have Surf.
- [ ] Before the Surf badge/move: no water spawns anywhere. Once you can use
      Surf, water Pokemon appear within ~15 s without re-entering the map; on
      a surf-only route with no land access they appear around you.
- [ ] A Cut tree / smashable rock / boulder walls off what is behind it until
      you can use Cut / Rock Smash / Strength; plain NPCs and item balls never
      make a corridor "unreachable".
- [ ] After hopping down a ledge, spawns above it (that you can no longer get
      back to) go away; spawns below it stay.
- [ ] After a warp inside a map or a long carry, the spawns re-form around you.
- [ ] Battles still never start from the flood fill (nothing happens when the
      map is entered next to a wild Pokemon).

## PMD follower recall (surfing)

- [ ] Start surfing with a PMDCollab follower: it shrinks into the player (sliding in
      and rising a little, with a red-white flush) over about 0.3 s, and is gone.
- [ ] Surf around, change direction, enter/leave a map while surfing: it stays inside;
      entering a map already surfing shows it inside from the start (no shrink replay).
- [ ] Step onto land: the follower grows back out of the player once it is itself on land
      (a step or two after you land), never standing on a water tile.
- [ ] You cannot talk to the follower while it is inside the player.
- [ ] HGSS / PokeMMO: unchanged -- the follower swims with its own water art.
- [ ] Tune `Config.PMD_RECALL_TICKS` (speed) and `PMD_RECALL_LIFT` (rise toward the body).

## FireRed / LeafGreen (new)

- [ ] Route 1 / Viridian Forest: visible land spawns stand and wander, walking
      onto one starts a battle with that exact Pokemon (species, level, nature,
      gender, shininess -- FRLG spawns get their personality from the engine's rng).
- [ ] Surfing (Cinnabar / Seafoam), caves (Mt. Moon, Rock Tunnel), Pallet water:
      water and cave spawns work; unreachable ground gets none.
- [ ] Safari Zone: NO visible spawns; the engine's own Safari battles (balls, bait)
      work as before. Same check in the Hoenn Safari Zone.
- [ ] Map names use the `FR_` / `LG_` convention: confirm spawns still appear and
      Modern Spawns (if installed) still redistributes species there.
- [ ] Follower, portraits and PMDCollab behave as on Hoenn.

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
- [x] Follower on/off: the party lead follows in the overworld when on; a
      party-lead swap changes the follower's sprite within a tick or two.
      (confirmed the follower appears and follows; haven't specifically
      checked a party-lead swap)
- [x] Sprite Style HGSS/PokeMMO vs PMDCollab: switching changes
      both already-spawned wild Pokemon AND the follower immediately, no
      map transition needed. In HGSS/PokeMMO, bigger species (e.g.
      Snorlax) visibly stand taller than small ones (e.g. Rattata), feet
      aligned to the same tile line -- not squashed to 16x16 and not
      floating above or sunk below the ground. (confirmed working; this
      is how a real left/right mirroring bug was caught -- a sprite
      visibly snapped sideways on every left<->right turn and every
      stand<->walk swap while walking left/right, HGSS/PokeMMO only. Fixed
      in lib/actor_renderer.lua's drawOffset -- re-check this after any
      future change to that function.)

## Release build (sprite atlas)

- [ ] Build with `python3 scripts/build-mod.py` (default atlas mode), install THAT ZIP (not a
      dev checkout with the real per-file sheets present), and confirm wild Pokemon and the
      follower still draw correctly in both Sprite Styles -- this is the only way to actually
      exercise `SpriteAtlas.image()`'s shard decode/slice path; the standalone tests can't (no
      love context) and a dev checkout never needs it (the real files always win first).

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
