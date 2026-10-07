-- Run: lua tests/spawn_manager_unit_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then
    failures = failures + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  else
    print("ok  " .. tostring(msg))
  end
end
local function eq(a, b, msg)
  check(a == b, string.format("%s (got %s expected %s)", msg, tostring(a), tostring(b)))
end

math.randomseed(42)

local fakeEngine = {}
local modules = {}
local optionStore = { enabled = true }
local mod = {
  id = "wilds_of_hoenn",
  options = { get = function(_, k) return optionStore[k] end },
  read = function(_, rel)
    local f = io.open(rel, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
  end,
}
local V = { path = ".", mod = mod }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  if name == "engine_patch" then
    modules[name] = fakeEngine
    return fakeEngine
  end
  local chunk = assert(loadfile("lib/" .. name .. ".lua"))
  local value = chunk(V)
  modules[name] = value
  return value
end

-- ------- fake engine: a 6x1 land strip, Treecko (national 252, internal
-- species id 999 to prove the national-dex conversion actually runs)
local tables = { ROUTE_1 = { land = { rate = 10, slots = {} } } }
fakeEngine.isSweetScentFacility = function() return false end
fakeEngine.ensureEncountersLoaded = function() return true end
fakeEngine.tableFor = function(mapId) return tables[mapId] end
fakeEngine.mapBounds = function() return 6, 1 end
fakeEngine.terrainAt = function(_x, _y) return "land" end
fakeEngine.canEnter = function() return true end
fakeEngine.isWater = function() return false end
fakeEngine.isGrass = function() return false end
fakeEngine.grassSheet = function() return nil end
fakeEngine.repelAllows = function() return true end
fakeEngine.trainerIds = function() return { otId = 1, otSecretId = 2 } end
fakeEngine.isShiny = function() return false end
fakeEngine.genderOf = function() return 0 end
fakeEngine.isCaught = function() return false end
fakeEngine.nationalFor = function(speciesId) if speciesId == 999 then return 252 end return nil end
fakeEngine.rollSweetScent = function(_mapId, terrain)
  return { species = 999, level = 5, personality = 123, terrainRolled = terrain }
end

local SpawnManager = V.require("spawn_manager")

-- ------- targetCount: the fixed density curve
eq(SpawnManager._targetCount(0), 0, "0 eligible cells -> 0 target")
eq(SpawnManager._targetCount(1), 1, "a handful of cells -> the floor (1)")
eq(SpawnManager._targetCount(1000), 8, "a huge area is capped at MAX_VISIBLE (8)")

-- ------- onMapEntered places visible wild Pokemon, converted to national dex
local sm = SpawnManager.new(mod)
sm:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
check(sm:count() > 0, "onMapEntered places at least one wild Pokemon")
local sampleId
for id, e in pairs(sm.entities) do
  sampleId = sampleId or id
  eq(e.dex, 252, "every entity's dex is the NATIONAL number, not the internal species id")
  eq(e.species, 999, "entity keeps the engine-internal species id for battle_trigger")
  eq(e.terrain, "land", "entity terrain matches the map (land-only in this fixture)")
  check(e.state == "available", "entity starts in the available state")
end

-- ------- floating/flying species flap while idle; ground species stay on
-- stand; a moving floater uses the walk pose
local SSrc = V.require("sprite_source")
local realIsFloater = SSrc.isFloater
SSrc.isFloater = function() return true end
local smF = SpawnManager.new(mod)
smF:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
local fe
for _, e in pairs(smF.entities) do fe = e break end
check(fe and fe.floater == true, "a floater species is flagged at spawn")
fe.behavior, fe.moving = "idle", false
fe.ticksUntilAction = 1e9
local poses = {}
for _ = 1, 100 do
  smF:tick(smF.game)
  local a = {}
  smF:collectActors(a)
  for _, actor in ipairs(a) do if actor.i == fe.id then poses[actor.walkPhase] = true end end
end
check(poses.walkA and poses.walkB and poses.stand, "an idle floater cycles walkA/stand/walkB")
fe.moving, fe.stepParity = true, true
local am = {}
smF:collectActors(am)
for _, actor in ipairs(am) do if actor.i == fe.id then eq(actor.walkPhase, "walkA", "a moving floater uses the walk pose") end end
SSrc.isFloater = function() return false end
local smG = SpawnManager.new(mod)
smG:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
local ge
for _, e in pairs(smG.entities) do ge = e break end
ge.behavior, ge.moving, ge.ticksUntilAction = "idle", false, 1e9
for _ = 1, 50 do smG:tick(smG.game) end
local ag = {}
smG:collectActors(ag)
for _, actor in ipairs(ag) do if actor.i == ge.id then eq(actor.walkPhase, "stand", "a ground species stays on stand") end end
SSrc.isFloater = realIsFloater

-- ------- _cellFree keeps spawns off the player's cell and the cell they are
-- stepping into
fakeEngine.playerCell = function() return { x = 2, y = 0, moving = true, targetX = 3, targetY = 0 } end
local smP = SpawnManager.new(mod)
check(not smP:_cellFree(2, 0), "no spawn on the cell the player stands on")
check(not smP:_cellFree(3, 0), "no spawn on the cell the player is stepping into")
check(smP:_cellFree(4, 0), "other cells stay free")
fakeEngine.playerCell = nil

-- ------- enabled=false spawns nothing
optionStore.enabled = false
local smOff = SpawnManager.new(mod)
smOff:onMapEntered("ROUTE_1", {})
eq(smOff:count(), 0, "Show Wild Mons off -> no spawns")
optionStore.enabled = true

-- ------- a species the engine can't convert to a national dex is skipped,
-- not spawned with a broken sprite lookup
fakeEngine.rollSweetScent = function() return { species = 111222, level = 5, personality = 1 } end
local smBad = SpawnManager.new(mod)
smBad:onMapEntered("ROUTE_1", {})
eq(smBad:count(), 0, "an unconvertible species id never gets spawned")
fakeEngine.rollSweetScent = function(_mapId, terrain)
  return { species = 999, level = 5, personality = 123, terrainRolled = terrain }
end

-- ------- entityAt / blocksCell
sm = SpawnManager.new(mod)
sm:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
local anyId, anyEntity
for id, e in pairs(sm.entities) do anyId, anyEntity = id, e break end
check(sm:entityAt(anyEntity.cellX, anyEntity.cellY) ~= nil, "entityAt finds the live entity on its cell")
check(sm:blocksCell(anyEntity.cellX, anyEntity.cellY), "blocksCell is true on an occupied cell")
check(not sm:blocksCell(-50, -50), "blocksCell is false off-map")

-- ------- markEncounterStarting removes it from entityAt (mid-battle mons
-- are not a collision target or a second trigger)
sm:markEncounterStarting(anyId)
check(sm:entityAt(anyEntity.cellX, anyEntity.cellY) == nil, "entityAt ignores an entity mid-battle")

-- ------- despawn removes it from both entities and order
sm:despawn(anyId)
check(sm.entities[anyId] == nil, "despawn removes the entity")
local stillInOrder = false
for _, id in ipairs(sm.order) do if id == anyId then stillInOrder = true end end
check(not stillInOrder, "despawn removes the id from draw order too")

-- ------- onMapExited clears everything
sm = SpawnManager.new(mod)
sm:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
check(sm:count() > 0, "sanity: something is spawned before exit")
sm:onMapExited()
eq(sm:count(), 0, "onMapExited clears all entities")
eq(#sm.order, 0, "onMapExited clears draw order")

-- ------- collectActors appends one actor per live entity with the shape
-- engine_patch's collectActors wrap expects
sm = SpawnManager.new(mod)
sm:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
local actors = {}
sm:collectActors(actors)
eq(#actors, sm:count(), "one actor per live entity")
for _, a in ipairs(actors) do
  eq(a.kind, "wild_mon", "actor kind is wild_mon")
  check(type(a.x) == "number" and type(a.y) == "number", "actor has world pixel coords")
  check(a.renderer ~= nil, "actor carries a renderer")
  check(a.elevation ~= nil, "actor has an elevation for applyDrawOrder")
end

-- ------- refill respects _cellFree: a fully-occupied strip refuses new spawns
tables.TINY = { land = { rate = 10, slots = {} } }
fakeEngine.mapBounds = function() return 1, 1 end
fakeEngine.terrainAt = function() return "land" end
local smTiny = SpawnManager.new(mod)
smTiny:onMapEntered("TINY", { world = { player = { cellX = -1, cellY = -1 } } })
eq(smTiny:count(), 1, "a 1x1 eligible area holds exactly one wild Pokemon")
smTiny:refill("land") -- should not error or duplicate on the same cell
eq(smTiny:count(), 1, "refill never double-occupies the only cell")
fakeEngine.mapBounds = function() return 6, 1 end -- restore for safety

-- ------- collectActors also appends the "sinking into grass" overlay
-- (lib/grass_cover.lua) for an entity whose cell is grass and whose feet
-- land in the tuft's draw band -- not just the entity's own actor.
fakeEngine.isGrass = function() return true end
fakeEngine.grassSheet = function() return { image = "fake_image", quadsFront = { [4] = "fake_quad" } } end
local smGrass = SpawnManager.new(mod)
smGrass:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
local grassActors = {}
smGrass:collectActors(grassActors)
local wildMonActors, grassOverlayActors = 0, 0
for _, a in ipairs(grassActors) do
  if a.kind == "wild_mon" then wildMonActors = wildMonActors + 1 end
  if a.kind == "field_effect_wild_grass" then grassOverlayActors = grassOverlayActors + 1 end
end
eq(wildMonActors, smGrass:count(), "collectActors still appends one wild_mon actor per entity")
eq(grassOverlayActors, smGrass:count(), "collectActors also appends one grass overlay per entity standing in grass")
fakeEngine.isGrass = function() return false end
fakeEngine.grassSheet = function() return nil end

-- ------- Sprite Style: threaded into each entity's renderer at spawn
-- time, and a live option change re-points every live entity without
-- despawning anything
-- a view of the mod with no PMD art (hermetic: a dev checkout may have a real bake on disk)
local function withoutPmd(base)
  return setmetatable({
    read = function(self, rel)
      if type(rel) == "string" and rel:find("assets/pmd/", 1, true) then return nil end
      return base.read(self, rel)
    end,
  }, { __index = base })
end
optionStore.sprite_style = "pokemmo"
local smStyle = SpawnManager.new(withoutPmd(mod))
smStyle:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
local anyStyleEntity
for _, e in pairs(smStyle.entities) do anyStyleEntity = e break end
eq(anyStyleEntity.renderer.style, "pokemmo", "a new spawn uses the current Sprite Style")

-- a saved style that no longer exists ("followers" was Kanto-only) falls back
-- to the default and rebuilds cleanly -- here PMD has no art in this fake mod,
-- so the HGSS / PokeMMO renderer is what draws
optionStore.sprite_style = "followers"
smStyle:refreshSpriteStyle()
eq(anyStyleEntity.renderer.style, "pokemmo",
  "refreshSpriteStyle rebuilds an already-spawned entity's renderer on a stale style")
eq(smStyle:count(), 1, "refreshSpriteStyle never despawns anything")
optionStore.sprite_style = "pokemmo" -- restore for safety

-- ------- PMDCollab style: renderers animate from a tick clock (Walk while
-- moving, Idle while standing) and a live style switch rebuilds them
local PMD_INDEX = [[{"version":1,"dex":{"252":{
  "walk":{"cw":30,"ch":26,"cols":4,"durations":[6,10,6,10],"ax":15.5,"ay":19.5,"shiny":false},
  "idle":{"cw":29,"ch":31,"cols":3,"durations":[40,4,2],"ax":15.5,"ay":25.5,"shiny":false}}}}]]
local pmdMod = {
  id = "wilds_of_hoenn", options = mod.options,
  read = function(_, rel) if rel == "assets/pmd/index.json" then return PMD_INDEX end return mod.read(_, rel) end,
}
V.mod = pmdMod
optionStore.sprite_style = "pmd"
local smPmd = SpawnManager.new(pmdMod)
smPmd:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
local pe
for _, e in pairs(smPmd.entities) do pe = e break end
check(pe and pe.renderer.isPmd == true, "pmd style spawns PmdRenderers for species with art")
pe.behavior, pe.moving, pe.ticksUntilAction = "idle", false, 1e9
pe.renderer.anim, pe.renderer.clock = "idle", 0
for _ = 1, 10 do smPmd:tick(smPmd.game) end
eq(pe.renderer.anim, "idle", "a standing PMD Pokemon plays Idle")
eq(pe.renderer.idleSpeed, 0.75, "wild Idle plays at 75% speed (25% slower)")
eq(pe.renderer.clock, 7.5, "its Idle clock advances 0.75 per field tick")
pe.fromX, pe.fromY, pe.targetX, pe.targetY = pe.cellX, pe.cellY, pe.cellX + 1, pe.cellY
pe.progress, pe.stepFrames, pe.moving = 0, 16, true
smPmd:tick(smPmd.game)
eq(pe.renderer.anim, "walk", "a stepping PMD Pokemon plays Walk")
for _ = 1, 20 do smPmd:tick(smPmd.game) end
eq(pe.renderer.anim, "idle", "and returns to Idle once the step lands")
pe.renderer.silhouette = true
optionStore.sprite_style = "pokemmo"
smPmd:refreshSpriteStyle()
check(not pe.renderer.isPmd and pe.renderer.style == "pokemmo", "switching away from pmd rebuilds an ActorRenderer")
check(pe.renderer.silhouette == true, "the rebuild keeps the silhouette")
optionStore.sprite_style = "pmd"
smPmd:refreshSpriteStyle()
check(pe.renderer.isPmd == true, "switching to pmd rebuilds a PmdRenderer")
optionStore.sprite_style = "pokemmo"
V.mod = mod

-- ------- reachable-only spawns: nothing appears where the player can't go
do
  local Config = V.require("config")
  local R_GAME = { world = { player = { cellX = -1, cellY = -1 } } }
  -- the 6-cell land strip is split by a wall: cells 0-2 are the player's side
  local wallAt = 3
  local builds = 0
  local playerAt = { x = 0, y = 0, moving = false }
  fakeEngine.reachStart = function() return { x = playerAt.x, y = playerAt.y, state = {} } end
  fakeEngine.reachMover = function()
    builds = builds + 1
    return function(x, y, dir, state)
      local d = ({ left = -1, right = 1 })[dir]
      if not d then return nil end
      local nx = x + d
      if nx < 0 or nx > 5 or nx == wallAt then return nil end
      return nx, y, state
    end
  end
  fakeEngine.playerCell = function() return playerAt end

  local smR = SpawnManager.new(mod)
  smR:onMapEntered("ROUTE_1", R_GAME)
  check(smR:count() > 0, "reachable cells still spawn")
  local allReachable = true
  for _, e in pairs(smR.entities) do if e.cellX >= wallAt then allReachable = false end end
  check(allReachable, "every spawn is on the player's side of the wall")
  local eligible = smR.source:eligibleCells("land")
  eq(#eligible, 3, "the other side of the wall is not eligible")
  check(builds == 1 and smR.reachCount == 3, "the area was measured once, 3 cells")

  -- the player ends up on the far side (a warp / ledge): re-measure and prune
  local stranded = nil
  for _, e in pairs(smR.entities) do stranded = e break end
  playerAt.x = 5
  wallAt = 4 -- the player's new pocket is cells 5 only... and 0-3 are cut off from it
  smR:tick(R_GAME)
  eq(builds, 2, "a player standing outside the reachable area triggers a re-measure")
  check(smR.entities[stranded.id] == nil, "spawns now out of reach are removed")
  for _, e in pairs(smR.entities) do check(e.cellX == 5, "what remains is on the player's new side") end

  -- a moving player is never measured mid-step
  playerAt.moving = true
  playerAt.x = 0
  local before = builds
  smR:tick(R_GAME)
  eq(builds, before, "no re-measure while the player is mid-step")
  playerAt.moving = false

  -- the slow timer picks up a changed world (Surf learned, a tree cut)
  playerAt.x, wallAt = 0, 3
  smR:_rebuildReach()
  local b2 = builds
  for _ = 1, Config.REACH_REBUILD_TICKS do smR:tick(R_GAME) end
  check(builds > b2, "the area is re-measured on a timer")

  -- the option off: no restriction at all
  Config.REACHABLE_SPAWNS = false
  local smOff2 = SpawnManager.new(mod)
  smOff2:onMapEntered("ROUTE_1", R_GAME)
  eq(#smOff2.source:eligibleCells("land"), 6, "REACHABLE_SPAWNS off: every land cell is eligible")
  Config.REACHABLE_SPAWNS = true

  -- no engine support (or no start): fail open, never an empty map
  fakeEngine.reachStart = function() return nil end
  local smOpen = SpawnManager.new(mod)
  smOpen:onMapEntered("ROUTE_1", R_GAME)
  eq(#smOpen.source:eligibleCells("land"), 6, "no start cell: no restriction")
  fakeEngine.reachStart, fakeEngine.reachMover, fakeEngine.playerCell = nil, nil, nil
  local smNone = SpawnManager.new(mod)
  smNone:onMapEntered("ROUTE_1", R_GAME)
  eq(#smNone.source:eligibleCells("land"), 6, "an engine without the reachability functions: no restriction")
  check(pcall(function() smNone:tick(R_GAME) end), "and ticking is safe")
end

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("spawn_manager_unit_test: all passed")
