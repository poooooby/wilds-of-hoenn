-- Run: lua tests/main_boot_unit_test.lua
-- Boots main.lua against a fake mod API and a fake src.core.game3.*
-- engine (via a monkeypatched global require, like
-- tests/engine_patch_unit_test.lua) -- covers the three outcomes
-- EnginePatch.isRse()/.probe() can produce without needing a real engine.
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

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local function makeMod()
  local wraps, events = {}, {}
  return {
    id = "wilds_of_hoenn",
    path = ".",
    log = { info = function() end, warn = function() end },
    read = function(_, rel) return readFile(rel) end,
    options = {
      define = function() end,
      get = function() return nil end,
    },
    events = {
      on = function(_, name, fn)
        events[name] = events[name] or {}
        events[name][#events[name] + 1] = fn
      end,
    },
    hooks = {
      wrap = function(_, name, fn)
        wraps[#wraps + 1] = name
        wraps[name] = fn
        return function() end
      end,
    },
    world = { game = {}, current = function() return { mapId = nil } end },
    exports = {},
    _wraps = wraps,
    _events = events,
  }
end

local function completeFakeEngine(layout)
  local fake = {}
  fake["src.core.game3.field_effects"] = { collectActors = function() end }
  fake["src.core.game3.objects"] = { blocks = function() return false end }
  fake["src.world.game3.Follower"] = { update = function() end, current = function() return nil end }
  fake["src.core.game3.battle_bridge"] = { startWild = function() return true end }
  fake["src.core.game3.encounters"] = {
    rollSweetScent = function() return nil end,
    terrainAt = function() return nil end,
    ensureLoaded = function() return true end,
    tableFor = function() return nil end,
    rules = function() return {} end,
    _h = { wild_level_allowed_by_repel = function() return true end },
  }
  fake["src.core.game3.collision"] = {
    isWater = function() return false end, isGrass = function() return false end,
    canEnter = function() return true end, inBounds = function() return true end,
    _widthCells = 1, _heightCells = 1,
  }
  fake["src.core.game3.pokemon"] = {
    national = function(id) return id end, speciesFromNational = function(n) return n end,
    speciesMeta = function() return {} end, isShiny = function() return false end,
    gender = function() return 0 end,
  }
  fake["src.core.game3.runtime"] = { getSession = function() return { party = {} } end }
  fake["src.core.game3.dex"] = { isCaught = function() return false end }
  fake["src.core.GameVersion"] = { layout = function() return layout end, get = function() return layout end }
  return fake
end

local realRequire = require
local function withFakeEngine(fake, fn)
  _G.require = function(name)
    if fake[name] ~= nil then return fake[name] end
    return realRequire(name)
  end
  local ok, err = pcall(fn)
  _G.require = realRequire
  if not ok then error(err, 0) end
end

local entry = assert(loadfile("main.lua"))()
check(type(entry) == "function", "main.lua returns an entry function")

-- ------- outcome 1: FireRed/LeafGreen boot -- installs nothing
withFakeEngine(completeFakeEngine("frlg"), function()
  local mod = makeMod()
  local ok = pcall(entry, mod)
  check(ok, "FRLG boot does not throw")
  eq(mod.exports.engineReady, false, "FRLG boot: engineReady stays false")
  check(mod.exports.spawnManager == nil, "FRLG boot: no spawnManager exported")
  eq(#mod._wraps, 0, "FRLG boot: no hooks wrapped")
end)

-- ------- outcome 2: RSE boot with a complete engine -- installs fully
withFakeEngine(completeFakeEngine("rse"), function()
  local mod = makeMod()
  local ok, err = pcall(entry, mod)
  check(ok, "RSE boot does not throw (" .. tostring(err) .. ")")
  eq(mod.exports.engineReady, true, "RSE boot: engineReady true")
  check(mod.exports.spawnManager ~= nil, "RSE boot: spawnManager exported")
  check(mod.exports.battleTrigger ~= nil, "RSE boot: battleTrigger exported")
  check(mod.exports.followerAdapter ~= nil, "RSE boot: followerAdapter exported")
  local sawEncounterRoll, sawFollowerSpawn = false, false
  for _, name in ipairs(mod._wraps) do
    if name == "encounter.roll" then sawEncounterRoll = true end
    if name == "world.follower.spawn" then sawFollowerSpawn = true end
  end
  check(sawEncounterRoll, "RSE boot: encounter.roll hook registered")
  check(sawFollowerSpawn, "RSE boot: world.follower.spawn hook registered")
  check(mod._events["map.entered"] ~= nil, "RSE boot: map.entered subscribed")
  check(mod._events["map.exited"] ~= nil, "RSE boot: map.exited subscribed")

  -- map.entered doesn't throw and reaches the spawn manager
  local okEnter, errEnter = pcall(mod._events["map.entered"][1], { mapId = "ROUTE_1" })
  check(okEnter, "map.entered handler does not throw (" .. tostring(errEnter) .. ")")
  eq(mod.exports.spawnManager.mapId, "ROUTE_1", "map.entered handler reaches the spawn manager")

  local okExit, errExit = pcall(mod._events["map.exited"][1], {})
  check(okExit, "map.exited handler does not throw (" .. tostring(errExit) .. ")")
end)

-- ------- outcome 3: RSE boot with a broken engine (probe fails) --
-- installs nothing, same as an unsupported generation
withFakeEngine(completeFakeEngine("rse"), function()
  package.loaded = package.loaded -- no-op, keeps linter quiet
  local fake = completeFakeEngine("rse")
  fake["src.core.game3.objects"] = nil -- simulate a moved/renamed engine field
  _G.require = function(name)
    if fake[name] ~= nil then return fake[name] end
    if name == "src.core.game3.objects" then error("module not found: " .. name, 0) end
    return realRequire(name)
  end
  local mod = makeMod()
  local ok, err = pcall(entry, mod)
  check(ok, "broken-engine RSE boot does not throw (" .. tostring(err) .. ")")
  eq(mod.exports.engineReady, false, "broken-engine boot: engineReady stays false")
  check(mod.exports.spawnManager == nil, "broken-engine boot: no spawnManager exported")
  _G.require = realRequire
end)

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("main_boot_unit_test: all passed")
