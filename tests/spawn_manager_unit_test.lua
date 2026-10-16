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
fakeEngine.safariActive = function() return false end
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
-- these tests are about the Walk <-> Idle switch itself: no grace period (see the linger tests in pmd_renderer_unit_test.lua)
V.require("config").PMD_WALK_LINGER = 0

-- ------- targetCount: the density curve (Normal unless a Spawn Amount row is given)
eq(SpawnManager._targetCount(0), 0, "0 eligible cells -> 0 target")
eq(SpawnManager._targetCount(1), 1, "a handful of cells -> the floor (1)")
eq(SpawnManager._targetCount(1000), 8, "a huge area is capped at MAX_VISIBLE (8)")
do
  local C = V.require("config")
  local L, N, H = C.SPAWN_AMOUNT.low, C.SPAWN_AMOUNT.normal, C.SPAWN_AMOUNT.high
  -- Normal is exactly the curve before the option existed: 1 + one per 20 tiles, at most 8
  for _, n in ipairs({ 1, 19, 20, 39, 40, 99, 140, 141, 1000 }) do
    local old = math.min(8, math.max(1, 1 + math.floor(n / 20)))
    eq(SpawnManager._targetCount(n, N), old, "Normal = the old curve at " .. n .. " tiles")
  end
  eq(SpawnManager._targetCount(0, H), 0, "High: no tiles -> none")
  for _, n in ipairs({ 1, 20, 60, 100, 1000 }) do
    local l, m, h = SpawnManager._targetCount(n, L), SpawnManager._targetCount(n, N), SpawnManager._targetCount(n, H)
    check(l <= m and m <= h, ("Low <= Normal <= High at %d tiles (%d, %d, %d)"):format(n, l, m, h))
  end
  eq(SpawnManager._targetCount(1000, L), 4, "Low caps at 4")
  eq(SpawnManager._targetCount(1000, H), 12, "High caps at 12")
  eq(SpawnManager._targetCount(100, L), 3, "Low: 100 tiles -> 3 (Normal 6)")
  eq(SpawnManager._targetCount(100, H), 9, "High: 100 tiles -> 9 (Normal 6)")
  local _, name = C.spawnAmount({ options = { get = function() return "bogus" end } })
  eq(name, "normal", "an unknown saved value reads as Normal")
end

-- ------- Spawn Amount in play: High fills more, lowering trims the extras at once
do
  local realBounds = fakeEngine.mapBounds
  fakeEngine.mapBounds = function() return 40, 5 end -- 200 land tiles
  optionStore.spawn_amount = "high"
  local smA = SpawnManager.new(mod)
  smA:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  eq(smA:count(), 12, "High on 200 tiles: 12 out")
  optionStore.spawn_amount = "low"
  smA:trimToAmount()
  local leaving = 0
  for _, e in pairs(smA.entities) do if e.state == "leaving" then leaving = leaving + 1 end end
  eq(leaving, 8, "lowered to Low: the 8 extra start leaving at once")
  eq(smA:_activeCountFor("land"), 4, "...and no longer count")
  for _ = 1, V.require("config").SPAWN_FX.leaveTicks + 1 do smA:tick(smA.game) end
  eq(smA:count(), 4, "once they have left: 4, and refill keeps it there")
  optionStore.spawn_amount = "normal"
  smA:tick(smA.game)
  eq(smA:count(), 8, "raised to Normal: refill tops up to 8")
  optionStore.spawn_amount = nil
  fakeEngine.mapBounds = realBounds
end

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

-- ------- a fled Pokemon disappearing at the end of its run: into grass, or a cave's dark
do
  local sm = SpawnManager.new(mod)
  sm:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  local e = sm.entities[sm.order[1]]
  local realGrass, realType = fakeEngine.isGrass, fakeEngine.mapType
  fakeEngine.mapType = function() return 3 end
  fakeEngine.isGrass = function() return false end
  eq(sm:fleeVanish(e), false, "on a path out in the open it stays")
  e.isFlyer = true
  fakeEngine.isGrass = function() return true end
  eq(sm:fleeVanish(e), false, "a bird never does (it flies off instead)")
  e.isFlyer = nil
  e.terrain = "water"
  eq(sm:fleeVanish(e), false, "nor a swimmer")
  e.terrain = "land"
  eq(sm:fleeVanish(e), true, "in grass it shrinks into it")
  eq(e.state, V.require("config").STATE.LEAVING, "...leaving the animated way (its tile's fx)")
  local e2 = sm.entities[sm.order[2]]
  if e2 then
    fakeEngine.isGrass = function() return false end
    fakeEngine.mapType = function() return 4 end
    eq(sm:fleeVanish(e2), true, "in a cave it fades out")
  end
  fakeEngine.isGrass, fakeEngine.mapType = realGrass, realType
end

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
-- swimming: a water spawn is cut at its waterline, unless it is a true flyer
local SSw = V.require("sprite_source")
check(pe.renderer.swimming == (pe.terrain == "water"), "a PMD spawn swims exactly when it is on water")
pe.terrain = "water"
smPmd:refreshSpriteStyle()
check(pe.renderer.swimming == true, "a PMD water spawn is drawn swimming")
SSw._setPmdWater({ [252] = true })
smPmd:refreshSpriteStyle()
check(pe.renderer.swimming == false, "...but a listed true flyer is drawn whole")
pe.terrain = "land"
smPmd:refreshSpriteStyle()
check(pe.renderer.swimming == false, "a land spawn never swims")
SSw._setPmdWater(nil)
optionStore.sprite_style = "pokemmo"
V.mod = mod

-- ------- FireRed / LeafGreen encounters carry no personality: the spawn rolls
-- one from the engine, so the battle Pokemon is the one on screen
do
  local realRoll, realRand = fakeEngine.rollSweetScent, fakeEngine.randomPersonality
  fakeEngine.rollSweetScent = function() return { species = 999, level = 7 } end -- no personality, as FRLG
  fakeEngine.randomPersonality = function() return 424242 end
  local smFr = SpawnManager.new(mod)
  smFr:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  local fe
  for _, e in pairs(smFr.entities) do fe = e break end
  check(fe ~= nil, "an encounter without a personality still spawns")
  eq(fe.personality, 424242, "...with a personality rolled from the engine")
  fakeEngine.rollSweetScent = function() return { species = 999, level = 7, personality = 77 } end
  local smRse = SpawnManager.new(mod)
  smRse:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  for _, e in pairs(smRse.entities) do fe = e break end
  eq(fe.personality, 77, "an encounter that already has one keeps it (RSE)")
  fakeEngine.randomPersonality = function() return nil end -- the engine's rng is unusable
  fakeEngine.rollSweetScent = function() return { species = 999, level = 7 } end
  local smNone = SpawnManager.new(mod)
  check(pcall(function() smNone:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } }) end),
    "an engine whose rng returns nothing never errors (the battle then rolls its own)")
  fakeEngine.rollSweetScent, fakeEngine.randomPersonality = realRoll, realRand
end

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
  check(smR.entities[stranded.id] and smR.entities[stranded.id].state == "leaving",
    "spawns now out of reach start leaving")
  for _ = 1, V.require("config").SPAWN_FX.leaveTicks + 1 do smR:tick(R_GAME) end
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
  check(builds > b2, "without a fingerprint, the area is re-measured on a timer")

  -- with a fingerprint: re-measured only when the world changed, once it settles
  local fp = 7
  fakeEngine.reachFingerprint = function() return fp end
  smR:_rebuildReach()
  local b3 = builds
  for _ = 1, Config.REACH_REBUILD_TICKS * 3 do smR:tick(R_GAME) end
  eq(builds, b3, "nothing changed: never re-measured, however long the player stands there")
  fp = 8 -- a tree cut
  for _ = 1, Config.REACH_CHECK_TICKS + Config.REACH_SETTLE_TICKS - 1 do smR:tick(R_GAME) end
  eq(builds, b3, "a change waits for the world to settle first")
  for _ = 1, Config.REACH_CHECK_TICKS * 2 do smR:tick(R_GAME) end
  eq(builds, b3 + 1, "...then re-measures exactly once")
  -- a boulder puzzle: a push every 2 s for 20 s, then a pause
  local b4 = builds
  for push = 1, 10 do
    fp = 100 + push
    for _ = 1, 120 do smR:tick(R_GAME) end
  end
  eq(builds, b4, "no re-measure while the boulders keep moving")
  for _ = 1, Config.REACH_CHECK_TICKS + Config.REACH_SETTLE_TICKS + Config.REACH_CHECK_TICKS do smR:tick(R_GAME) end
  eq(builds, b4 + 1, "one re-measure for the whole run of pushes, after the pause")
  -- pushed out and back again: nothing to do
  local b5 = builds
  fp = 999
  for _ = 1, Config.REACH_CHECK_TICKS do smR:tick(R_GAME) end
  fp = 110
  for _ = 1, Config.REACH_SETTLE_TICKS * 3 do smR:tick(R_GAME) end
  eq(builds, b5, "a change undone before it settled costs nothing")
  fakeEngine.reachFingerprint = nil

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

-- ------- tooling: a chosen species on a tile near the player, or a battle with it
do
  fakeEngine.mapBounds = function() return 6, 1 end
  fakeEngine.terrainAt = function() return "land" end
  fakeEngine.randomPersonality = function() return 777 end
  fakeEngine.playerCell = function() return { x = 5, y = 0, moving = false } end
  local smT = SpawnManager.new(mod)
  smT:onMapEntered("ROUTE_1", { world = { player = { cellX = 5, cellY = 0 } } })
  smT:clearAll()
  local ok, cell = smT:spawnSpecies(999, 12)
  check(ok == true and cell ~= nil, "spawnSpecies places it")
  check(cell and math.abs(cell.x - 5) <= 3 and cell.x ~= 5, "...within 3 tiles of the player, never on their tile")
  local made
  for _, e in pairs(smT.entities) do made = e end
  eq(made and made.species, 999, "it is the species asked for")
  eq(made and made.level, 12, "...at the level asked for")
  eq(made and made.dex, 252, "...drawn through the usual national dex lookup")
  eq(made and made.shiny, false, "...not shiny unless asked")

  smT:clearAll()
  ok = smT:spawnSpecies(999, 5, { shiny = true })
  for _, e in pairs(smT.entities) do made = e end
  check(ok == true and made.shiny == true, "shiny = true makes it shiny")

  smT:clearAll()
  ok = smT:spawnSpecies(999, 5, { radius = 0 })
  eq(ok, nil, "a radius with no free eligible tile reports why")
  eq(select(2, smT:spawnSpecies(nil, 5)), "no species", "no species is refused")
  fakeEngine.playerCell = nil
  eq(select(2, smT:spawnSpecies(999, 5)), "no player", "no player cell is refused")

  local started
  fakeEngine.startWild = function(game, enc, opts) started = { game = game, enc = enc } return true end
  smT.game = { g = 1 }
  eq(smT:battleSpecies(999, 20, { shiny = true }), true, "battleSpecies starts a battle")
  check(started and started.enc.species == 999 and started.enc.level == 20 and started.enc.shiny == true,
    "...with that species, level and shininess")
  fakeEngine.startWild = function() return nil, "busy" end
  local bok, why = smT:battleSpecies(999, 20)
  check(bok == nil and why == "busy", "a battle that will not start says why")
end

-- ------- Sweet Scent calls 2-3 wild Pokemon over (instead of the engine's instant battle)
do
  local C = V.require("config")
  local realBounds, realRepel, realCell = fakeEngine.mapBounds, fakeEngine.repelAllows, fakeEngine.playerCell
  fakeEngine.mapBounds = function() return 40, 9 end
  fakeEngine.playerCell = function() return { x = 20, y = 4, moving = false } end
  local smS = SpawnManager.new(mod)
  smS:onMapEntered("ROUTE_1", { world = { player = { cellX = 20, cellY = 4 } } })
  local before = smS:count()
  fakeEngine.repelAllows = function() return false end -- Sweet Scent ignores Repel
  for trial = 1, 20 do
    local came = smS:sweetScent()
    check(came == nil or (came >= C.SWEET_SCENT.min and came <= C.SWEET_SCENT.max) or trial > 1,
      "first use: 2 or 3 called over")
    if trial == 1 then
      local lured = 0
      for _, e in pairs(smS.entities) do
        if e.lured then
          lured = lured + 1
          local d = math.max(math.abs(e.cellX - 20), math.abs(e.cellY - 4))
          check(d >= 1 and d <= 4, ("lured one 1-4 tiles from the player (%d)"):format(d))
          check(e.lured.ticks == C.SWEET_SCENT.lureTicks, "lured for the full lure time")
        end
      end
      check(lured == came, "every one that came is marked lured")
      check(smS:count() == before + came, "they come on top of the ones already out")
      check(smS:_activeCountFor("land") == before, "and do not count toward the Spawn Amount target")
      local hearts = {}
      smS:collectActors(hearts)
      local n = 0
      for _, a in ipairs(hearts) do if a.kind == "ow_sweet_scent_hearts" then n = n + 1 end end
      check(n == came, "each lured one has hearts over it")
      -- they stay put while lured, then wander like any other
      local e
      for _, x in pairs(smS.entities) do if x.lured then e = x break end end
      local cx, cy = e.cellX, e.cellY
      e.behavior, e.ticksUntilAction = "roam", 0
      for _ = 1, 200 do smS:tick(smS.game) end
      check(e.cellX == cx and e.cellY == cy and e.lured, "a lured one stays put")
      e.lured.ticks = 1
      smS:tick(smS.game)
      check(e.lured == nil, "the lure wears off: a normal wanderer again")
      break
    end
  end
  fakeEngine.repelAllows = realRepel
  -- nothing eligible close by: 0 (the engine's "nothing here" text, no battle)
  fakeEngine.playerCell = function() return { x = 200, y = 200, moving = false } end
  eq(smS:sweetScent(), 0, "no spawn cell within 4 tiles: none came (fail text)")
  -- the visible spawns off: nil -> the engine's own Sweet Scent
  optionStore.enabled = false
  eq(smS:sweetScent(), nil, "Show Wild Mons off: the engine's own Sweet Scent")
  optionStore.enabled = true
  fakeEngine.mapBounds, fakeEngine.playerCell = realBounds, realCell
end

-- ------- arriving / leaving (lib/spawn_fx.lua): rise out of the grass, surface, or fade
do
  local C = V.require("config")
  local realBounds, realGrass, realWater = fakeEngine.mapBounds, fakeEngine.isGrass, fakeEngine.isWater
  fakeEngine.mapBounds = function() return 40, 5 end
  local smF = SpawnManager.new(mod)
  smF:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  local anyFx = false
  for _, e in pairs(smF.entities) do if e.fx then anyFx = true end end
  check(not anyFx and smF.filled, "the map's first fill is instant (no effect)")

  -- after a battle a Pokemon is gone at once; its replacement fades in (no grass / water here)
  local first
  for id in pairs(smF.entities) do first = id break end
  smF:despawn(first)
  check(smF.entities[first] == nil, "despawn after a battle: gone at once")
  smF:tick(smF.game)
  local new
  for _, e in pairs(smF.entities) do if e.fx then new = e end end
  check(new and new.fx.kind == "appear" and new.fx.mode == "fade", "its replacement arrives (fade: not grass or water)")
  check(new.renderer.alpha ~= nil and new.renderer.alpha < 0.2, "...starting nearly invisible")
  check(smF:entityAt(new.cellX, new.cellY) == new, "an arriving Pokemon can already be met")
  local found = false
  for _, t in ipairs(smF:fightTargets()) do if t == new then found = true end end
  check(not found, "but the Battler does not pick it until it has arrived")
  local cx, cy = new.cellX, new.cellY
  new.behavior, new.ticksUntilAction = "roam", 0
  for _ = 1, C.SPAWN_FX.appearTicks do smF:tick(smF.game) end
  check(new.fx == nil and new.renderer.alpha == nil, "it finishes and the renderer is left as normal")
  check(new.cellX == cx and new.cellY == cy, "no wandering off while arriving")

  -- grass: rises (sink) with the rustle drawn on its tile
  fakeEngine.isGrass = function() return true end
  local rustled = 0
  fakeEngine.grassRustle = function() rustled = rustled + 1 return { quadsFront = { [1] = 1, [2] = 2, [3] = 3, [4] = 4 } }, { { 1, 10 }, { 2, 10 }, { 3, 10 }, { 4, 10 } } end
  local g
  for id in pairs(smF.entities) do g = id break end
  smF:despawn(g)
  smF:tick(smF.game)
  local ge
  for _, e in pairs(smF.entities) do if e.fx then ge = e end end
  check(ge and ge.fx.mode == "grass" and rustled >= 1, "in grass it rises, and the grass rustles")
  check(ge.renderer.act and ge.renderer.act.sink > 0.8, "...starting below the grass line")
  local acts = {}
  smF:collectActors(acts)
  local r = 0
  for _, a in ipairs(acts) do if a.kind == "ow_spawn_rustle" then r = r + 1 end end
  check(r == 1, "the rustle is drawn on its tile")
  for _ = 1, C.SPAWN_FX.appearTicks do smF:tick(smF.game) end
  check(ge.renderer.act == nil, "standing again: the renderer's act is cleared")

  -- water: surfaces with a ripple
  fakeEngine.isGrass = realGrass
  fakeEngine.isWater = function() return true end
  local ripples = 0
  fakeEngine.startRipple = function() ripples = ripples + 1 return true end
  local w
  for id in pairs(smF.entities) do w = id break end
  smF:despawn(w)
  smF:tick(smF.game)
  local we
  for _, e in pairs(smF.entities) do if e.fx then we = e end end
  check(we and we.fx.mode == "water" and we.rings ~= nil, "on water it surfaces inside growing rings")
  local wa = {}
  smF:collectActors(wa)
  local rings = 0
  for _, a in ipairs(wa) do if a.kind == "ow_spawn_rings" then rings = rings + 1 end end
  check(rings == 1, "the rings are drawn on its tile")
  for _ = 1, V.require("spawn_fx").ringsTicks() do smF:tick(smF.game) end
  check(we.rings == nil, "and are gone once all three have spread out")

  -- leaving: no longer met or counted, removed once it has sunk away
  for _ = 1, C.SPAWN_FX.appearTicks do smF:tick(smF.game) end
  local l
  for _, e in pairs(smF.entities) do l = e break end
  local before = smF:_activeCountFor("land")
  smF:despawn(l.id, { animate = true })
  check(l.state == "leaving" and l.fx.kind == "leave", "an animated despawn starts leaving")
  check(smF:entityAt(l.cellX, l.cellY) == nil, "a leaving Pokemon can no longer be met")
  check(smF:_activeCountFor("land") == before - 1, "and no longer counts")
  check(smF.entities[l.id] ~= nil, "it is still drawn while it goes")
  for _ = 1, C.SPAWN_FX.leaveTicks + 1 do smF:tick(smF.game) end
  check(smF.entities[l.id] == nil, "then it is gone")

  fakeEngine.mapBounds, fakeEngine.isGrass, fakeEngine.isWater = realBounds, realGrass, realWater
  fakeEngine.grassRustle, fakeEngine.startRipple = nil, nil
end

-- ------- the roaming legendary is one Pokemon: never more than one copy out
do
  local realRoll, realBounds = fakeEngine.rollSweetScent, fakeEngine.mapBounds
  fakeEngine.mapBounds = function() return 40, 5 end -- room for 8
  -- every roll wins the roamer (a FireRed player on Suicune's map got five of it)
  fakeEngine.rollSweetScent = function()
    return { species = 999, level = 50, personality = 77, roamer = true, hp = 40 }
  end
  local smR = SpawnManager.new(mod)
  smR:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  local roamers = 0
  for _, e in pairs(smR.entities) do if e.roamer then roamers = roamers + 1 end end
  eq(roamers, 1, "every roll wins the roamer: still only one out")
  local targets = smR:fightTargets()
  eq(#targets, 0, "the companion Battler never targets the roamer")
  fakeEngine.rollSweetScent, fakeEngine.mapBounds = realRoll, realBounds
end

-- ------- the Safari Zone: wild Pokemon show, but the companion Battler never fights them
do
  fakeEngine.safariActive = function() return true end
  local smS = SpawnManager.new(mod)
  smS:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  check(smS:count() > 0, "Safari Zone: wild Pokemon spawn")
  eq(#smS:fightTargets(), 0, "...but the Battler never targets them (Safari Balls only)")
  fakeEngine.safariActive = function() return false end
end

-- ------- off-screen wild Pokemon are not drawn (each draw takes a gen3-hd-sprites layer)
do
  fakeEngine.viewSize = function() return 240, 160 end
  local smV = SpawnManager.new(mod)
  smV:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  local n = smV:count()
  local all = {}
  smV:collectActors(all)
  local mons = 0
  for _, a in ipairs(all) do if a.kind == "wild_mon" then mons = mons + 1 end end
  eq(mons, n, "no camera: every wild Pokemon is drawn (older engine)")
  local seen = {}
  smV:collectActors(seen, 0, 0)
  mons = 0
  for _, a in ipairs(seen) do if a.kind == "wild_mon" then mons = mons + 1 end end
  eq(mons, n, "camera on the strip: all of them are in view")
  local far = {}
  smV:collectActors(far, 5000, 5000)
  mons = 0
  for _, a in ipairs(far) do if a.kind == "wild_mon" then mons = mons + 1 end end
  eq(mons, 0, "camera far away: none drawn")
  local I = SpawnManager._inView
  check(I({ px = 240 + 127, py = 0 }, 0, 0, 240, 160), "just inside the margin past the right edge: drawn")
  check(not I({ px = 240 + 128, py = 0 }, 0, 0, 240, 160), "at the margin: not drawn")
  check(I({ px = 0, py = -127 }, 0, 0, 240, 160), "a big sprite whose feet are just above the view: drawn")
  local refl = {}
  smV:reflections(refl, 5000, 5000)
  eq(#refl, 0, "no reflections for Pokemon out of view")
  fakeEngine.viewSize = nil
end

print("")
-- ------- an engaged wild Pokemon caught mid-step finishes the step, then stands still
do
  local smE = SpawnManager.new(mod)
  smE:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  local en
  for _, e in pairs(smE.entities) do en = e break end
  en.engaged = true
  en.fromX, en.fromY, en.targetX, en.targetY = en.cellX, en.cellY, en.cellX + 1, en.cellY
  en.progress, en.stepFrames, en.moving = 0, 4, true
  local tx = en.targetX
  for _ = 1, 6 do smE:tick(smE.game) end
  check(en.moving == false and en.cellX == tx, "it lands on the cell it was stepping into")
  local x, y = en.cellX, en.cellY
  for _ = 1, 30 do smE:tick(smE.game) end
  check(en.cellX == x and en.cellY == y and not en.moving, "...and then stands its ground")
end

-- ------- a shiny chain's bonus reaches the visible spawns (Modern Spawns)
do
  local MS = V.require("modern_spawns_bridge")
  local realBonus = MS.chainBonus
  local asked = {}
  MS.chainBonus = function(species) asked[#asked + 1] = species return { shiny = 0, perfectIvs = 6 } end
  local smC = SpawnManager.new(mod)
  smC:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  local ce
  for _, e in pairs(smC.entities) do ce = e break end
  check(ce ~= nil and #asked > 0 and asked[1] == ce.species, "each spawn asks for its species' chain bonus")
  local perfect = 0
  for _, v in pairs(ce and ce.ivs or {}) do if v == 31 then perfect = perfect + 1 end end
  eq(perfect, 6, "...and carries the perfect stats into its battle")
  MS.chainBonus = function() return nil end
  local smN = SpawnManager.new(mod)
  smN:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  local ne
  for _, e in pairs(smN.entities) do ne = e break end
  eq(ne and ne.ivs, nil, "no chain: IVs are left to the engine")
  MS.chainBonus = realBonus
end

-- ------- Flying types arrive and leave by air (lib/sky_flyers.lua)
do
  local C = V.require("config")
  local SkyFlyers = V.require("sky_flyers")
  fakeEngine.isFlying = function(s) return s == 999 end
  fakeEngine.isWaterType = function() return false end
  fakeEngine.skyAllowed = function() return true end
  fakeEngine.mapType = function() return 3 end
  fakeEngine.neighbourMapIds = function() return {} end
  fakeEngine.weatherId = function() return 0 end
  fakeEngine.isWall = function() return false end
  fakeEngine.coversActors = function() return false end
  fakeEngine.objectOn = function() return false end
  fakeEngine.isWarpCell = function() return false end
  fakeEngine.signCells = function() return {} end
  fakeEngine.playerIsRunning = function() return false end
  local realBounds = fakeEngine.mapBounds
  fakeEngine.mapBounds = function() return 40, 5 end
  local realPlayer = fakeEngine.playerCell
  local player = { x = 200, y = 200, moving = false } -- far away: every spawn may fly
  fakeEngine.playerCell = function() return player end

  SkyFlyers._resetFlies() -- earlier sections asked with no isFlying in the fake engine
  local smS = SpawnManager.new(mod)
  local sky = SkyFlyers.new(mod)
  smS.sky = sky
  sky:onMapEntered("ROUTE_1")
  smS:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  local before = smS:count()
  local anyFx = false
  for _, e in pairs(smS.entities) do
    if e.fx then anyFx = true end
    check(e.isFlyer, "a Flying-type spawn is marked a flyer")
  end
  check(not anyFx, "the map's first fill is instant, nobody swoops")

  -- one goes: the refill's new one comes down from the sky
  local firstId = smS.order[1]
  smS:despawn(firstId)
  smS:tick(smS.game)
  eq(smS:count(), before, "the refill replaces it at once (it counts while still in the air)")
  local lander
  for _, e in pairs(smS.entities) do if e.fx and e.fx.mode == "swoop" then lander = e end end
  check(lander ~= nil and lander.fx.kind == "land", "the new Flying type swoops in instead of rising out of the grass")
  if lander then
    eq(smS:entityAt(lander.cellX, lander.cellY), nil, "in the air: it cannot be met (no contact, no block)")
    local targets = 0
    for _, t in ipairs(smS:fightTargets()) do if t == lander then targets = targets + 1 end end
    eq(targets, 0, "...nor fought by the Battler")
    local actors = {}
    smS:collectActors(actors, 0, 0)
    local skyActor = false
    for _, a in ipairs(actors) do
      if a.kind == "sky_mon" or a.kind == "sky_mon_far" then skyActor = true end
      check(a.i ~= lander.id or a.kind ~= "wild_mon", "it is not drawn as a ground actor while flying")
    end
    check(skyActor, "it is drawn as a flyer")
    for _ = 1, 400 do smS:tick(smS.game) if not lander.fx then break end end
    eq(lander.fx, nil, "it lands")
    eq(smS:entityAt(lander.cellX, lander.cellY), lander, "landed: it can be met")
    eq(lander.state, "available", "...and is an ordinary wild Pokemon")
  end

  -- leaving: a Flying type takes off instead of sinking
  local leaverId = smS.order[1]
  smS:despawn(leaverId, { animate = true })
  local leaver = smS.entities[leaverId]
  check(leaver and leaver.state == "leaving" and leaver.fx and leaver.fx.mode == "swoop" and leaver.fx.kind == "leave",
    "an animated despawn of a Flying type: it flies off")
  for _ = 1, 400 do smS:tick(smS.game) if not smS.entities[leaverId] then break end end
  eq(smS.entities[leaverId], nil, "...and is gone once out of sight")

  -- churn: after its time on the ground a flyer takes off by itself
  local stayer
  for _, e in pairs(smS.entities) do if e.state == "available" and not e.fx then stayer = e break end end
  if stayer then
    stayer.groundStay, stayer.groundAge, stayer.moving = 1, 0, false
    stayer.ticksUntilAction = 999
    smS:tick(smS.game)
    check(stayer.state == "leaving" and stayer.fx and stayer.fx.kind == "leave", "a flyer leaves after its ground stay")
  end

  -- the player walks onto its cell while it comes down: it takes straight off again
  for _ = 1, 400 do smS:tick(smS.game) end
  local victimId = smS.order[1]
  smS:despawn(victimId)
  smS:tick(smS.game)
  local incoming
  for _, e in pairs(smS.entities) do if e.fx and e.fx.kind == "land" then incoming = e end end
  if incoming then
    player.x, player.y = incoming.cellX, incoming.cellY
    for _ = 1, 400 do smS:tick(smS.game) if incoming.state ~= "available" or not incoming.fx then break end end
    eq(incoming.state, "leaving", "landing on the player: it takes off again instead")
    check(not (incoming.fx and incoming.fx.mode == "swoop"), "...the usual way: right by the player, no swoop")
    player.x, player.y = 200, 200
  else
    check(false, "a lander came for the player test")
  end

  -- a spawn within 3 tiles of the player arrives the usual way (no swoop up close)
  do
    for _ = 1, 400 do smS:tick(smS.game) end
    local id = smS.order[1]
    local cell = smS.entities[id]
    player.x, player.y = cell.cellX + 1, cell.cellY
    smS:despawn(id)
    -- refill picks any free cell: count what arrives near the player
    local near, swoopNear = 0, 0
    for _ = 1, 400 do
      if near >= 5 then break end -- refills pick random cells: run until a few came near
      local victim = smS.order[1]
      smS:despawn(victim)
      smS:tick(smS.game)
      for _, e in pairs(smS.entities) do
        if e.fx and (e.fx.kind == "land" or e.fx.kind == "appear") and e.fxSeen == nil then
          e.fxSeen = true
          if math.max(math.abs(e.cellX - player.x), math.abs(e.cellY - player.y)) <= 3 then
            near = near + 1
            if e.fx.mode == "swoop" then swoopNear = swoopNear + 1 end
          end
        end
      end
    end
    check(near > 0, "some spawns came within 3 tiles of the player")
    eq(swoopNear, 0, "...and none of them swooped in")
    player.x, player.y = 200, 200
    for _ = 1, 400 do smS:tick(smS.game) end
  end

  -- Flying Mons off: the usual rise / fade
  optionStore.flyers = false
  for _ = 1, 400 do smS:tick(smS.game) end
  local plainId = smS.order[1]
  smS:despawn(plainId)
  smS:tick(smS.game)
  local plain
  for _, e in pairs(smS.entities) do if e.fx and e.fx.kind == "appear" then plain = e end end
  check(plain ~= nil and plain.fx.mode ~= "swoop", "Flying Mons off: it arrives the usual way")
  optionStore.flyers = nil

  -- a map change mid-flight frees everything at once
  smS:clearAll()
  eq(smS:count(), 0, "a map change clears flyers too")

  fakeEngine.isFlying = nil
  fakeEngine.mapBounds = realBounds
  fakeEngine.playerCell = realPlayer
  check(C.FLYERS.land.groundStay[1] > 0, "a flyer stays a while on the ground")
end

-- ------- Wild Reacts: a running player close by startles them; one reacting is no Battler target
do
  local realCell, realBounds = fakeEngine.playerCell, fakeEngine.mapBounds
  fakeEngine.mapBounds = function() return 40, 5 end
  local smR = SpawnManager.new(mod)
  smR:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  local target
  for _, e in pairs(smR.entities) do target = target or e end
  local player = { x = target.cellX + 2, y = target.cellY, moving = true }
  fakeEngine.playerCell = function() return player end
  fakeEngine.playerIsRunning = function() return true end
  fakeEngine.leadPartyMon = function() return { level = 50, species = 1 } end -- they are all weak
  smR:tick(smR.game)
  check(target.react ~= nil, "running close by: it reacts")
  local isTarget = false
  for _, t in ipairs(smR:fightTargets()) do if t == target then isTarget = true end end
  check(not isTarget, "...and is no Battler target meanwhile")
  smR:calmReactions()
  eq(target.react, nil, "switching the option off calms everyone at once")
  optionStore.wild_reacts = false
  target.reactUntil = 0
  smR:tick(smR.game)
  eq(target.react, nil, "Wild Reacts off: nobody reacts")
  optionStore.wild_reacts = nil
  fakeEngine.playerCell, fakeEngine.mapBounds = realCell, realBounds
  fakeEngine.playerIsRunning, fakeEngine.leadPartyMon = nil, nil
end

-- ------- a chaser left out on the path (its chase cut short) goes home; with Wild Reacts
-- off it fades away instead
do
  local saved = {}
  for _, k in ipairs({ "playerCell", "mapBounds", "terrainAt", "cellFree", "fieldBusy" }) do saved[k] = fakeEngine[k] end
  fakeEngine.mapBounds = function() return 40, 5 end
  -- grass x < 20, a path beyond it
  fakeEngine.terrainAt = function(x) if x < 20 then return "land" end return nil end
  fakeEngine.cellFree = function(x, y) return x >= 0 and y >= 0 and x < 40 and y < 5 end
  local player = { x = 39, y = 4, moving = false }
  fakeEngine.playerCell = function() return player end
  local smS = SpawnManager.new(mod)
  smS:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  local stray
  for _, e in pairs(smS.entities) do stray = stray or e end
  -- it chased out onto the path, then the chase was cut short (no reaction running)
  stray.cellX, stray.cellY, stray.px, stray.py = 23, 2, 23 * 16, 2 * 16
  stray.chaseHome, stray.react, stray.fx = { x = 15, y = 2 }, nil, nil
  smS:tick(smS.game)
  check(stray.react and stray.react.mode == "return", "a stray on the path is sent home")
  for _ = 1, 600 do
    if not stray.react then break end
    smS:tick(smS.game)
  end
  check(stray.cellX < 20, "...it walked back onto its grass (" .. stray.cellX .. ")")
  eq(stray.chaseHome, nil, "...and forgot the way")
  eq(smS:get(stray.id), stray, "...still there")

  -- Wild Reacts off: nothing walks it home, so it fades out (once the field is free)
  stray.cellX, stray.px, stray.chaseHome = 25, 25 * 16, { x = 15, y = 2 }
  optionStore.wild_reacts = false
  fakeEngine.fieldBusy = function() return true end
  smS:tick(smS.game)
  local STATE = V.require("config").STATE
  eq(stray.state, STATE.AVAILABLE, "Wild Reacts off, the field busy: it waits")
  fakeEngine.fieldBusy = function() return false end
  smS:tick(smS.game)
  eq(stray.state, STATE.LEAVING, "...then it fades away, never stuck on the path")
  optionStore.wild_reacts = nil
  for k, v in pairs(saved) do fakeEngine[k] = v end
end

-- ------- under the sea (a Dive map): fish swim in as a shadow; everything is drawn whole
do
  local WaterLife = V.require("water_life")
  local saved = {}
  for _, k in ipairs({ "mapType", "terrainAt", "isWater", "mapBounds", "eggGroups", "heightDm", "playerCell", "tableFor" }) do
    saved[k] = fakeEngine[k]
  end
  fakeEngine.mapType = function() return 5 end
  fakeEngine.terrainAt = function() return "water" end
  fakeEngine.isWater = function() return true end
  fakeEngine.mapBounds = function() return 40, 5 end
  fakeEngine.tableFor = function() return { water = { rate = 4, slots = {} } } end
  local fish = true
  fakeEngine.eggGroups = function() if fish then return 12, 12 end return 2, 2 end
  fakeEngine.heightDm = function() return 5 end
  local player = { x = 200, y = 200, moving = false }
  fakeEngine.playerCell = function() return player end

  local smU = SpawnManager.new(mod)
  local wl = WaterLife.new(mod)
  smU.water = wl
  wl:onMapEntered("UNDERWATER_ROUTE124")
  smU:onMapEntered("UNDERWATER_ROUTE124", { world = { player = { cellX = -1, cellY = -1 } } })
  check(smU.underwater, "a Dive map")
  local any
  for _, e in pairs(smU.entities) do any = e break end
  check(any and any.renderer.presentation ~= "swimming", "an underwater Pokemon is drawn whole, not cut at a surface")

  smU:despawn(smU.order[1])
  smU:tick(smU.game)
  local newcomer
  for _, e in pairs(smU.entities) do if e.fx then newcomer = e end end
  check(newcomer and newcomer.fx.mode == "swim" and newcomer.fx.kind == "land", "a fish swims in under the sea")
  if newcomer then
    eq(smU:entityAt(newcomer.cellX, newcomer.cellY), nil, "...and cannot be met before it has arrived")
    for _ = 1, 400 do smU:tick(smU.game) if not newcomer.fx then break end end
    eq(newcomer.fx, nil, "it arrives")
    eq(smU:entityAt(newcomer.cellX, newcomer.cellY), newcomer, "...and can be met")
    smU:despawn(newcomer.id, { animate = true })
    check(newcomer.fx and newcomer.fx.mode == "swim" and newcomer.fx.kind == "leave", "leaving, it swims off")
  end

  fish = false
  for _ = 1, 400 do smU:tick(smU.game) end
  smU:despawn(smU.order[1])
  smU:tick(smU.game)
  local other
  for _, e in pairs(smU.entities) do if e.fx and e.fx.kind == "appear" then other = e end end
  check(other ~= nil and other.fx.mode == "fade", "a non-fish fades in under the sea (no surface to break)")

  for k, v in pairs(saved) do fakeEngine[k] = v end
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("spawn_manager_unit_test: all passed")
