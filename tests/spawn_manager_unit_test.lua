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

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("spawn_manager_unit_test: all passed")
