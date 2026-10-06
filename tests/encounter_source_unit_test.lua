-- Run: lua tests/encounter_source_unit_test.lua
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

local fakeEngine = {}
local modules = {}
local V = { path = "." }
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

local sweetScentFacilityMaps = {}
local tables = {}
local terrainGrid = {}

fakeEngine.isSweetScentFacility = function(mapId) return sweetScentFacilityMaps[mapId] == true end
fakeEngine.ensureEncountersLoaded = function() return true end
fakeEngine.tableFor = function(mapId) return tables[mapId] end
fakeEngine.mapBounds = function() return 4, 4 end
fakeEngine.terrainAt = function(x, y) return terrainGrid[y] and terrainGrid[y][x] end

local EncounterSource = V.require("encounter_source")

-- ------- a 4x4 map: a 2x2 water pool in the corner, land everywhere else
for y = 0, 3 do
  terrainGrid[y] = {}
  for x = 0, 3 do
    terrainGrid[y][x] = (x < 2 and y < 2) and "water" or "land"
  end
end
tables.ROUTE_1 = { land = { rate = 10, slots = {} }, water = { rate = 5, slots = {} } }

local src = EncounterSource.new({})
src:loadMap("ROUTE_1")
check(src:isEligible(), "ROUTE_1 is eligible (has both areas)")
local land = src:eligibleCells("land")
local water = src:eligibleCells("water")
eq(#land, 12, "12 land cells (4x4 minus the 2x2 pool)")
eq(#water, 4, "4 water cells (the 2x2 pool)")

-- eligibleCells returns a fresh copy each call (copy-on-read contract)
local land2 = src:eligibleCells("land")
check(land2 ~= land, "eligibleCells returns a new table each call")
land2[1].x = -999
eq(src:eligibleCells("land")[1].x, land[1].x, "mutating a returned cell doesn't affect the source")

-- ------- a map with only a land table never reports water cells, even
-- though the terrain grid has water tiles (defensive: no water TABLE means
-- no water spawns regardless of tile flags)
tables.LAND_ONLY = { land = { rate = 10, slots = {} } }
local srcLandOnly = EncounterSource.new({})
srcLandOnly:loadMap("LAND_ONLY")
eq(#srcLandOnly:eligibleCells("water"), 0, "no water table -> no water cells even over water tiles")
eq(#srcLandOnly:eligibleCells("land"), 12, "land table still finds its cells")

-- ------- a map with no table at all is not eligible, and the cell scan
-- is skipped entirely (no wasted work)
tables.EMPTY = nil
local srcEmpty = EncounterSource.new({})
srcEmpty:loadMap("EMPTY")
check(not srcEmpty:isEligible(), "a map with no wild table is not eligible")
eq(#srcEmpty:eligibleCells("land"), 0, "no cells scanned for an ineligible map")

-- ------- Battle Pike / Battle Pyramid maps are skipped outright
sweetScentFacilityMaps.WILD_ROOM = true
tables.WILD_ROOM = { land = { rate = 10, slots = {} } } -- even with a table present
local srcFacility = EncounterSource.new({})
srcFacility:loadMap("WILD_ROOM")
check(not srcFacility:isEligible(), "a sweet-scent-facility map is never eligible")
eq(#srcFacility:eligibleCells("land"), 0, "facility map cell scan is skipped")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("encounter_source_unit_test: all passed")
