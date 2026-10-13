-- Run: lua tests/modern_spawns_bridge_unit_test.lua
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
local other -- what mod:find("modern_spawns") answers
local mod = { find = function(_, id) if id == "modern_spawns" then return other end end }
local V = { path = ".", mod = mod }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  if name == "engine_patch" then modules[name] = fakeEngine return fakeEngine end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end

-- engine: national dex n -> internal 1000 + n; ROUTE_101's land table
fakeEngine.speciesForNational = function(n) if n == 9999 then return nil end return 1000 + n end
local tables = {
  ROUTE_101 = {
    land = { rate = 10, slots = {
      { species = 261, minLevel = 2, maxLevel = 3 },
      { species = 261, minLevel = 4, maxLevel = 5 },
      { species = 263, minLevel = 2, maxLevel = 3 },
    } },
    water = { rate = 5, slots = { { species = 129, minLevel = 5, maxLevel = 10 } } },
  },
}
fakeEngine.tableFor = function(mapId) return tables[mapId] end

local calls = {}
local generated = {
  grass = { rate = 10, slots = {
    { species = "RATTATA", minLevel = 2, maxLevel = 3 },
    { species = "PIDGEY", minLevel = 4, maxLevel = 5 },
    { species = "NOPE", minLevel = 2, maxLevel = 3 },
  } },
  water = { rate = 5, slots = { { species = "WOOPER", minLevel = 5, maxLevel = 10 } } },
}
local dexOf = { RATTATA = 19, PIDGEY = 16, WOOPER = 194, NOPE = 9999, SNORLAX = 143 }
local legendary
local active, generation = true, 3
local function makeOther()
  return { exports = {
    apiVersion = 1,
    isActive = function() return active end,
    generation = function() return generation end,
    drawFor = function(mapId, terrain) calls[#calls + 1] = terrain return generated[terrain] end,
    legendaryFor = function() return legendary end,
    profileOf = function(id) return dexOf[id] and { dex = dexOf[id] } or nil end,
  } }
end
other = makeOther()

local Bridge = V.require("modern_spawns_bridge")
local function enc(species, level, extra)
  local e = { species = species, level = level, personality = 77 }
  for k, v in pairs(extra or {}) do e[k] = v end
  return e
end

-- the rolled slot's generated species replaces the engine's, level/personality kept
local out = Bridge.apply("ROUTE_101", "land", enc(261, 2))
eq(out.species, 1019, "slot 1 -> Rattata (national 19 -> internal)")
eq(out.level, 2, "rolled level is kept")
eq(out.personality, 77, "personality is kept")

-- same engine species in two slots: the level picks the slot
eq(Bridge.apply("ROUTE_101", "land", enc(261, 5)).species, 1016, "level 5 -> slot 2 -> Pidgey")

-- water uses the water table
eq(Bridge.apply("ROUTE_101", "water", enc(129, 7)).species, 1194, "water slot -> Wooper")
eq(calls[#calls], "water", "water asks drawFor for the water table")

-- the caller's encounter is never mutated
local original = enc(261, 2)
Bridge.apply("ROUTE_101", "land", original)
eq(original.species, 261, "input encounter is not mutated")

-- speciesId follows when present
eq(Bridge.apply("ROUTE_101", "land", enc(261, 2, { speciesId = 261 })).speciesId, 1019,
  "speciesId is swapped alongside species")

-- passthrough cases return the very same table
local e = enc(263, 2)
eq(Bridge.apply("ROUTE_101", "land", e).species, 263,
  "a generated species the engine has no slot for keeps the engine's own")
e = enc(999, 2)
check(Bridge.apply("ROUTE_101", "land", e) == e, "an encounter matching no slot passes through")
e = enc(261, 2, { roamer = true })
check(Bridge.apply("ROUTE_101", "land", e) == e, "roamers are never touched")
e = enc(261, 2)
check(Bridge.apply("ROUTE_999", "land", e) == e, "a map with no engine table passes through")

-- legendary roll wins over the slot
legendary = "SNORLAX"
eq(Bridge.apply("ROUTE_101", "land", enc(261, 2)).species, 1143, "LEGENDARIES roll replaces the slot")
-- ...but never with the roaming legendary's species while it is still out: it exists once
fakeEngine.roamerNow = function() return { species = 1143, roamer = true } end
check(Bridge.apply("ROUTE_101", "land", enc(261, 2)).species ~= 1143,
  "the roamer's species is not placed by the LEGENDARIES roll while it roams")
fakeEngine.roamerNow = function() return { species = 1245, roamer = true } end
eq(Bridge.apply("ROUTE_101", "land", enc(261, 2)).species, 1143, "another species roaming: no effect")
fakeEngine.roamerNow = function() return nil end
eq(Bridge.apply("ROUTE_101", "land", enc(261, 2)).species, 1143,
  "roamer defeated (no longer active): the species is on offer again")
fakeEngine.roamerNow = nil
legendary = nil

-- inactive / wrong generation / absent / old api -> untouched
active = false
e = enc(261, 2)
check(Bridge.apply("ROUTE_101", "land", e) == e, "inactive Modern Spawns passes through")
active = true
generation = 1
check(Bridge.apply("ROUTE_101", "land", e) == e, "a non-Gen-3 table shape passes through")
generation = 3
other = nil
check(Bridge.apply("ROUTE_101", "land", e) == e, "Modern Spawns not installed passes through")
other = makeOther()
other.exports.apiVersion = 0
check(Bridge.apply("ROUTE_101", "land", e) == e, "apiVersion < 1 passes through")
other = makeOther()
other.exports.drawFor = function() error("boom") end
check(Bridge.apply("ROUTE_101", "land", e) == e, "an erroring API falls through to the engine's encounter")

-- ------- shiny chains
do
  active, generation = true, 3
  legendary = nil
  other = makeOther()
  -- an older Modern Spawns without chains: nothing changes, nothing breaks
  eq(Bridge.chainBonus(1019), nil, "no chain exports: no bonus")
  check(pcall(Bridge.chainRecord, 1019, "win"), "no chain exports: recording is a harmless no-op")
  eq(Bridge.apply("ROUTE_101", "land", enc(261, 2)).species, 1019, "...and spawns are as before")

  local forced, recorded, asked = nil, {}, {}
  other.exports.chainSpeciesFor = function(mapId, terrain) asked[#asked + 1] = terrain return forced end
  other.exports.chainBonus = function(species)
    if species == 1143 then return { shiny = 0.25, perfectIvs = 2 } end
    return nil
  end
  other.exports.chainRecord = function(species, result) recorded[#recorded + 1] = { species, result } end

  forced = "SNORLAX"
  local out = Bridge.apply("ROUTE_101", "land", enc(261, 4))
  eq(out.species, 1143, "the chained species takes the slot's place (national 143)")
  eq(out.level, 4, "...at the rolled level")
  eq(out.personality, 77, "...same personality")
  eq(asked[#asked], "grass", "it is asked with the bridge's terrain name")
  legendary = "PIDGEY"
  eq(Bridge.apply("ROUTE_101", "land", enc(261, 4)).species, 1016, "a legendary roll still comes first")
  legendary = nil
  forced = nil
  eq(Bridge.apply("ROUTE_101", "land", enc(261, 4)).species, 1016, "no forced species: the slot swap as usual")
  forced = "NOPE"
  eq(Bridge.apply("ROUTE_101", "land", enc(261, 4)).species, 1016, "a forced species the engine lacks is skipped")
  forced = nil
  local roamer = enc(380, 40, { roamer = true })
  forced = "SNORLAX"
  eq(Bridge.apply("ROUTE_101", "land", roamer).species, 380, "a roamer is never chained away")
  forced = nil

  local b = Bridge.chainBonus(1143)
  check(b and b.shiny == 0.25 and b.perfectIvs == 2, "chainBonus passes Modern Spawns' answer through")
  eq(Bridge.chainBonus(1019), nil, "...nil for another species")
  Bridge.chainRecord(1143, "win")
  check(recorded[1] and recorded[1][1] == 1143 and recorded[1][2] == "win", "chainRecord reaches Modern Spawns")
  other.exports.chainBonus = function() error("boom") end
  eq(Bridge.chainBonus(1143), nil, "a failing export answers nil, never throws")
  active = false
  other.exports.chainBonus = function() return { shiny = 1 } end
  eq(Bridge.chainBonus(1143), nil, "Modern Spawns inactive: no chain")
  other = nil
  eq(Bridge.chainBonus(1143), nil, "not installed: no chain")
  active = true
  other = makeOther()
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("all passed")
