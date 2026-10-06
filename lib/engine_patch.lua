-- The ONLY module in this mod that touches src/core/game3 internals.
--
-- Gen1Recomp's game3 (FRLG/RSE) engine has no mod seam for a visible
-- overworld actor: mod.world:spawnNpc returns "not supported", ow.entities
-- is a read-only snapshot rebuilt every access, the field renderer has no
-- draw hook, and collision has no mod hook (docs/rfcs/0014 proposes one but
-- it is not implemented). This mod ships before that lands, so it reaches
-- into the engine directly via the `engine_internals` permission, declared
-- in manifest.json.
--
-- Every patch here is:
--   1. probed first: we check the exact field we are about to wrap exists
--      and is a function, with a comment pinning the engine file/line we
--      read it from. If any probe fails, EnginePatch.install() returns
--      false and nothing is touched -- the caller (main.lua) must then
--      disable visible spawns and fall fully back to vanilla.
--   2. reversible: the original function is stored and install() can be
--      called again after uninstall() (hot reload) without double-wrapping.
--   3. pcall-guarded at the call site: a Lua error inside our wrapper logs
--      once and falls through to the original behaviour rather than
--      corrupting the engine's draw/collision/tick loop.
--
-- tests/engine_patch_probe_test.lua runs this file's probes against a real
-- gen1recomp checkout (luajit) so an engine update that moves one of these
-- fields fails loudly instead of silently breaking spawns in the field.

local EnginePatch = {}

-- name -> { mod = "src.core.game3.xxx", field = "yyy" }. Kept as data so the
-- probe test and install() share one list and can't drift apart.
EnginePatch.TARGETS = {
  -- field_view.lua:748 FieldEffects.collectActors(actors) runs every frame
  -- right before FieldView.applyDrawOrder; any actor it appends with a
  -- `renderer` field is drawn via renderer:draw(x,y,camX,camY,facing,
  -- walkPhase,false) (field_view.lua:569).
  collectActors = { mod = "src.core.game3.field_effects", field = "collectActors" },

  -- objects.lua:989 Objects.blocks(tx, ty, exceptLocalId, elevation) is the
  -- one choke point for "is this cell occupied by something solid": it
  -- backs player movement (collision.lua:1003 entityBlocks, called from
  -- Collision.canEnter), event-NPC movement (objects.lua:1536) and trainer
  -- sight lines (trainer_sight.lua:245). Wrapping it alone makes our wild
  -- Pokemon solid to the player, to NPCs, and invisible to trainer sight
  -- checks, all at once.
  blocks = { mod = "src.core.game3.objects", field = "blocks" },

  -- field.lua:238 calls Follower.update(game) every field tick, right after
  -- Player.update. We piggyback our own per-tick spawn/behavior update here
  -- so we don't need a second hook into the tick loop.
  followerUpdate = { mod = "src.world.game3.Follower", field = "update" },

  -- battle_bridge.lua:740 BattleBridge.startWild(mod, game, encounter, opts)
  -- keeps personality/ivs/roamer, unlike mod.world:startWildBattle which
  -- only takes species+level. We call it directly so the battle is the
  -- exact mon the player saw standing in the grass.
  startWild = { mod = "src.core.game3.battle_bridge", field = "startWild" },
}

-- Read-only engine calls we depend on but never wrap. Probed the same way
-- so a rename anywhere in this list is caught by the same test.
EnginePatch.READONLY = {
  rollSweetScent = { mod = "src.core.game3.encounters", field = "rollSweetScent" },
  terrainAt = { mod = "src.core.game3.encounters", field = "terrainAt" },
  ensureLoaded = { mod = "src.core.game3.encounters", field = "ensureLoaded" },
  tableFor = { mod = "src.core.game3.encounters", field = "tableFor" },
  isWater = { mod = "src.core.game3.collision", field = "isWater" },
  isGrass = { mod = "src.core.game3.collision", field = "isGrass" },
  canEnter = { mod = "src.core.game3.collision", field = "canEnter" },
  inBounds = { mod = "src.core.game3.collision", field = "inBounds" },
  national = { mod = "src.core.game3.pokemon", field = "national" },
  speciesFromNational = { mod = "src.core.game3.pokemon", field = "speciesFromNational" },
  speciesMeta = { mod = "src.core.game3.pokemon", field = "speciesMeta" },
  isShiny = { mod = "src.core.game3.pokemon", field = "isShiny" },
  gender = { mod = "src.core.game3.pokemon", field = "gender" },
  getSession = { mod = "src.core.game3.runtime", field = "getSession" },
  isCaught = { mod = "src.core.game3.dex", field = "isCaught" },
  layout = { mod = "src.core.GameVersion", field = "layout" },
  gameVersionGet = { mod = "src.core.GameVersion", field = "get" },
}

local function loadModule(path)
  local ok, mod = pcall(require, path)
  if not ok then return nil, mod end
  return mod
end

--- True only on Ruby/Sapphire/Emerald (layout "rse"). FireRed/LeafGreen
--- ("frlg") have their own encounter_rules module and a different map id
--- convention (Gen3Compat.gen3MapId's "FR_" prefix); this mod targets RSE
--- only. main.lua calls this before EnginePatch.probe()/install() so an
--- FRLG boot never even attempts the patches.
function EnginePatch.isRse()
  local GameVersion = loadModule(EnginePatch.READONLY.layout.mod)
  if not GameVersion then return false end
  local ok, id = pcall(GameVersion.get)
  if not ok then return false end
  local okL, layout = pcall(GameVersion.layout, id)
  return okL and layout == "rse"
end

--- Checks every target + readonly entry resolves to a function, without
--- installing anything. Used by install() and reused verbatim by the probe
--- test so the two can never check different things.
function EnginePatch.probe()
  local missing = {}
  local function check(list)
    for name, spec in pairs(list) do
      local mod, err = loadModule(spec.mod)
      if not mod then
        missing[#missing + 1] = name .. " (" .. spec.mod .. " did not load: " .. tostring(err) .. ")"
      elseif type(mod[spec.field]) ~= "function" then
        missing[#missing + 1] = name .. " (" .. spec.mod .. "." .. spec.field .. " is "
          .. type(mod[spec.field]) .. ", expected function)"
      end
    end
  end
  check(EnginePatch.TARGETS)
  check(EnginePatch.READONLY)
  return #missing == 0, missing
end

local function safeCall(log, label, fn, ...)
  local ok, a, b, c = pcall(fn, ...)
  if not ok then
    log:warn("[wilds_of_hoenn] %s wrapper error (falling back to engine behaviour): %s",
      label, tostring(a))
    return nil
  end
  return a, b, c
end

--- Installs every wrap. `hooks` is a table of callbacks this mod supplies:
---   hooks.collectActors(actors)       -- append our wild-mon actors
---   hooks.blocks(tx, ty, exceptId, elevation) -> true/false
---   hooks.followerTick(game)          -- run after the real Follower.update
--- install() does nothing destructive until probe() has already passed;
--- main.lua is expected to call probe() first and only call install() when
--- it returns true.
function EnginePatch.install(hooks, log)
  if EnginePatch._installed then return true end
  local ok, missing = EnginePatch.probe()
  if not ok then
    return false, missing
  end

  local originals = {}

  local FieldEffects = loadModule(EnginePatch.TARGETS.collectActors.mod)
  originals.collectActors = FieldEffects.collectActors
  FieldEffects.collectActors = function(actors)
    originals.collectActors(actors)
    if hooks.collectActors then
      safeCall(log, "collectActors", hooks.collectActors, actors)
    end
  end

  local Objects = loadModule(EnginePatch.TARGETS.blocks.mod)
  originals.blocks = Objects.blocks
  Objects.blocks = function(tx, ty, exceptLocalId, elevation)
    if originals.blocks(tx, ty, exceptLocalId, elevation) then return true end
    if hooks.blocks then
      local blocked = safeCall(log, "blocks", hooks.blocks, tx, ty, exceptLocalId, elevation)
      if blocked then return true end
    end
    return false
  end

  local Follower = loadModule(EnginePatch.TARGETS.followerUpdate.mod)
  originals.followerUpdate = Follower.update
  Follower.update = function(game)
    originals.followerUpdate(game)
    if hooks.followerTick then
      safeCall(log, "followerTick", hooks.followerTick, game)
    end
  end

  EnginePatch._originals = originals
  EnginePatch._installed = true
  return true
end

--- Restores every wrapped function to what it was before install(). Safe to
--- call when not installed (no-op). Used by hot reload and tests.
function EnginePatch.uninstall()
  if not EnginePatch._installed then return end
  local originals = EnginePatch._originals

  local FieldEffects = loadModule(EnginePatch.TARGETS.collectActors.mod)
  if FieldEffects and originals.collectActors then
    FieldEffects.collectActors = originals.collectActors
  end

  local Objects = loadModule(EnginePatch.TARGETS.blocks.mod)
  if Objects and originals.blocks then
    Objects.blocks = originals.blocks
  end

  local Follower = loadModule(EnginePatch.TARGETS.followerUpdate.mod)
  if Follower and originals.followerUpdate then
    Follower.update = originals.followerUpdate
  end

  EnginePatch._originals = {}
  EnginePatch._installed = false
end

--- BattleBridge.startWild is called directly, not wrapped -- we never need
--- to intercept other callers of it, only to call it ourselves with a full
--- encounter record (species, level, personality, ivs, roamer).
function EnginePatch.startWild(game, encounter, opts)
  local BattleBridge = loadModule(EnginePatch.TARGETS.startWild.mod)
  if not BattleBridge then return nil, "battle_bridge unavailable" end
  return BattleBridge.startWild(nil, game, encounter, opts)
end

--- Thin read-only accessors so the rest of this mod never calls `require`
--- directly -- every engine touch point is listed above and visible in one
--- file.
function EnginePatch.encounters()
  return loadModule(EnginePatch.READONLY.rollSweetScent.mod)
end

function EnginePatch.collision()
  return loadModule(EnginePatch.READONLY.isWater.mod)
end

function EnginePatch.pokemon()
  return loadModule(EnginePatch.READONLY.national.mod)
end

--- The current map's cell bounds, read off Collision's own internal grid
--- state (collision.lua:30, set on every map load) the same way the
--- engine's own Encounters.encounterTypeAt reads Collision._mapDef. Not a
--- public accessor -- there isn't one -- so this is proxied by the
--- `inBounds` probe above rather than probed directly: both are "Collision
--- still tracks per-map bounds the shape we expect" checks. Returns 0, 0
--- with no map loaded (matches the fields' own reset default).
function EnginePatch.mapBounds()
  local Collision = loadModule(EnginePatch.READONLY.isWater.mod)
  if not Collision then return 0, 0 end
  return tonumber(Collision._widthCells) or 0, tonumber(Collision._heightCells) or 0
end

--- Engine-internal species id -> national dex number (e.g. internal 277 ->
--- national 252, Treecko). pokemon.lua:293. Returns nil for an id the
--- current game doesn't know (egg placeholder, SPECIES_NONE).
function EnginePatch.nationalFor(speciesId)
  local Pokemon = EnginePatch.pokemon()
  if not Pokemon then return nil end
  local ok, nat = pcall(Pokemon.national, speciesId)
  if ok and type(nat) == "number" and nat > 0 then return nat end
  return nil
end

--- National dex number -> engine-internal species id. pokemon.lua:281.
function EnginePatch.speciesForNational(nat)
  local Pokemon = EnginePatch.pokemon()
  if not Pokemon then return nil end
  local ok, id = pcall(Pokemon.speciesFromNational, nat)
  if ok and type(id) == "number" and id > 0 then return id end
  return nil
end

--- The live save's { trainerId = publicId, secretId = secretId }, or nil
--- with no session (no save loaded, or between field sessions).
function EnginePatch.trainerIds()
  local Runtime = loadModule(EnginePatch.READONLY.getSession.mod)
  local ok, session = pcall(Runtime and Runtime.getSession)
  if not (ok and type(session) == "table") then return nil end
  return { otId = tonumber(session.trainerId) or 0, otSecretId = tonumber(session.secretId) or 0 }
end

--- pokemon.lua:1397 Pokemon.isShiny({personality, otId, otSecretId}).
--- `otId`/`otSecretId` default to the live save's trainer when omitted, so
--- a wild encounter's shiny-ness always matches the player who would catch
--- it, exactly like the real game.
function EnginePatch.isShiny(personality, otId, otSecretId)
  local Pokemon = EnginePatch.pokemon()
  if not Pokemon then return false end
  if otId == nil or otSecretId == nil then
    local ids = EnginePatch.trainerIds()
    otId = otId or (ids and ids.otId) or 0
    otSecretId = otSecretId or (ids and ids.otSecretId) or 0
  end
  local ok, shiny = pcall(Pokemon.isShiny, { personality = personality, otId = otId, otSecretId = otSecretId })
  return ok and shiny == true
end

--- pokemon.lua:396 Pokemon.gender(species, personality) -> MON_MALE (0x00) |
--- MON_FEMALE (0xFE) | MON_GENDERLESS (0xFF).
function EnginePatch.genderOf(species, personality)
  local Pokemon = EnginePatch.pokemon()
  if not Pokemon then return nil end
  local ok, g = pcall(Pokemon.gender, species, personality)
  if ok then return g end
  return nil
end

--- encounters.lua:170 terrainAt(cx, cy) -> "land" | "water" | nil. The
--- authoritative per-cell encounter classification: ROM metatile encounter
--- type, falling back to Collision.isWater/isGrass. Never reimplemented.
function EnginePatch.terrainAt(cx, cy)
  local Encounters = EnginePatch.encounters()
  if not Encounters then return nil end
  local ok, t = pcall(Encounters.terrainAt, cx, cy)
  return ok and t or nil
end

function EnginePatch.isWater(cx, cy)
  local Collision = EnginePatch.collision()
  if not Collision then return false end
  local ok, w = pcall(Collision.isWater, cx, cy)
  return ok and w == true
end

function EnginePatch.isGrass(cx, cy)
  local Collision = EnginePatch.collision()
  if not Collision then return false end
  local ok, g = pcall(Collision.isGrass, cx, cy)
  return ok and g == true
end

--- collision.lua:1035 canEnter(game, tx, ty, opts). Read-only here: our
--- wild Pokemon use this to decide their OWN steps, the same rules the
--- player follows (ledges, elevation, water/land dismount). The `blocks`
--- wrap above is the only place this mod affects the player's canEnter.
function EnginePatch.canEnter(game, tx, ty, opts)
  local Collision = EnginePatch.collision()
  if not Collision then return false end
  local ok, enter = pcall(Collision.canEnter, game, tx, ty, opts)
  return ok and enter == true
end

--- encounters.lua:314 tableFor(mapId) -> the map's { land, water, rocks }
--- areas, already resolved through Altering Cave variants (pick_variant).
function EnginePatch.tableFor(mapId)
  local Encounters = EnginePatch.encounters()
  if not Encounters then return nil end
  local ok, t = pcall(Encounters.tableFor, mapId)
  if ok then return t end
  return nil
end

function EnginePatch.ensureEncountersLoaded()
  local Encounters = EnginePatch.encounters()
  if not Encounters then return false end
  local ok, loaded = pcall(Encounters.ensureLoaded)
  return ok and loaded == true
end

--- encounter_rules/rse.lua:494 rollSweetScent(mapId, terrain): a full
--- encounter (species, level, personality, ivs, roamer) with ability bias,
--- Synchronize/Cute Charm, outbreaks and roamers all applied, but WITHOUT
--- the per-step encounter-rate gate -- exactly what a visible spawn needs
--- (it is generated once, not re-rolled every tile). `terrain` is "land" or
--- "water".
function EnginePatch.rollSweetScent(mapId, terrain)
  local Encounters = EnginePatch.encounters()
  if not Encounters then return nil end
  local ok, enc = pcall(Encounters.rollSweetScent, mapId, terrain)
  if ok then return enc end
  return nil
end

--- encounter_rules/rse.lua:478 sweetScentFacility(mapId): true on Battle
--- Pike / Battle Pyramid maps, where wild generation is special-cased and
--- this mod does not add visible spawns (see docs/ARCHITECTURE.md).
function EnginePatch.isSweetScentFacility(mapId)
  local Encounters = EnginePatch.encounters()
  if not (Encounters and Encounters.rules) then return false end
  local ok, rules = pcall(Encounters.rules)
  if not ok then return false end
  local f = rules and rules.sweetScentFacility
  if type(f) ~= "function" then return false end
  local okF, result = pcall(f, mapId)
  return okF and result == true
end

--- encounters.lua's internal H.wild_level_allowed_by_repel(level): false
--- when a Repel is active and `level` is below the lead party mon's level
--- (pokefirered/src/wild_encounter.c:601). Honoured the same way the
--- vanilla step roll does, without reimplementing the Repel rule.
function EnginePatch.repelAllows(level)
  local Encounters = EnginePatch.encounters()
  local h = Encounters and Encounters._h
  if not (h and h.wild_level_allowed_by_repel) then return true end
  local ok, allowed = pcall(h.wild_level_allowed_by_repel, level)
  if ok then return allowed ~= false end
  return true
end

--- The first healthy, non-egg party member's engine-internal species id, or
--- nil with no session/party/eligible mon. Mirrors the same "lead" scan
--- Encounters._h.wild_level_allowed_by_repel does over session.party --
--- read-only data access, not a function call, so it is covered by the
--- `getSession` probe above rather than its own entry.
function EnginePatch.leadPartySpecies()
  local Runtime = loadModule(EnginePatch.READONLY.getSession.mod)
  local ok, session = pcall(Runtime and Runtime.getSession)
  if not (ok and type(session) == "table" and type(session.party) == "table") then
    return nil
  end
  for i = 1, 6 do
    local mon = session.party[i]
    if type(mon) == "table" and (tonumber(mon.hp) or tonumber(mon.currentHp) or 1) > 0
        and not mon.isEgg and not mon.egg then
      return tonumber(mon.species)
    end
  end
  return nil
end

--- src/world/game3/Follower.lua's current npc record (nil when no
--- follower is spawned -- e.g. the option is off or mid-map-transition).
--- `npc.sprite` is a renderer, read by Follower.actor() at draw time; see
--- lib/follower_adapter.lua's followerTick.
function EnginePatch.followerCurrent()
  local Follower = loadModule(EnginePatch.TARGETS.followerUpdate.mod)
  if not (Follower and Follower.current) then return nil end
  local ok, npc = pcall(Follower.current)
  if ok then return npc end
  return nil
end

--- Whether the player's Pokedex has `speciesId` (engine-internal id) seen
--- as caught/owned. dex.lua:242. Returns false with no session/dex.
function EnginePatch.isCaught(speciesId)
  local Runtime = loadModule(EnginePatch.READONLY.getSession.mod)
  local Dex = loadModule(EnginePatch.READONLY.isCaught.mod)
  if not (Runtime and Dex) then return false end
  local ok, session = pcall(Runtime.getSession)
  if not (ok and type(session) == "table" and session.dex) then return false end
  local okC, caught = pcall(Dex.isCaught, session.dex, speciesId)
  return okC and caught == true
end

return EnginePatch
