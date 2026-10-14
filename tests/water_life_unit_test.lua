-- Run: lua tests/water_life_unit_test.lua
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

math.randomseed(5)

-- species: 1 Magikarp, 2 Goldeen, 3 Horsea, 4 Tentacool, 5 Wailmer, 6 Feebas, 7 Octillery
local NAT = { 129, 118, 116, 72, 320, 349, 224 }
local EGG = { { 12, 14 }, { 12, 12 }, { 2, 14 }, { 9, 9 }, { 5, 12 }, { 2, 14 }, { 2, 12 } }
local HEIGHT = { 9, 6, 4, 9, 20, 6, 9 }
local fake = {}
local optionStore = { sprite_style = "pokemmo" }
local mod = { options = { get = function(_, k) return optionStore[k] end }, read = function() return nil end }
local modules = { engine_patch = fake }
local V = { path = ".", mod = mod }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end
fake.nationalFor = function(s) return NAT[s] end
fake.eggGroups = function(s) local e = EGG[s] if e then return e[1], e[2] end end
fake.heightDm = function(s) return HEIGHT[s] end
fake.tableFor = function()
  return { fishing = { slots = { { species = 1 }, { species = 1 }, { species = 2 }, { species = 5 } } },
           water = { slots = { { species = 4 }, { species = 3 }, { species = 6 }, { species = 7 } } } }
end
fake.mapType = function() return 3 end
fake.isWater = function(x, y) return x >= 0 and y >= 0 and x < 30 and y < 20 end -- a 30 x 20 lake
fake.objectOn = function() return false end
local ripples = 0
fake.startRipple = function() ripples = ripples + 1 return true end
fake.viewSize = function() return 480, 320 end
fake.playerCell = function() return { x = 0, y = 0, moving = false } end

local WL = V.require("water_life")
local Config = V.require("config")

-- ------- who leaps, who surfaces
do
  check(WL.isFish(1), "Magikarp leaps")
  check(WL.isFish(2), "Goldeen leaps")
  check(WL.isFish(6), "Feebas leaps (a fish, though not Water 2)")
  check(not WL.isFish(3), "never Horsea")
  check(not WL.isFish(7), "never Octillery (not a fish)")
  check(not WL.isFish(4), "Tentacool is no fish")
  check(not WL.isFish(5), "Wailmer is too big to leap")
  check(WL.isWhale(5), "Wailmer surfaces")
  local fish, whales = WL.poolFor("ROUTE_105")
  eq(#fish, 3, "the map's fish: Magikarp, Goldeen, Feebas")
  eq(#whales, 1, "...and its whale: Wailmer")
end

-- ------- splash and spray particles
do
  check(#WL.splash(1, 3) > 0, "a splash throws droplets")
  eq(#WL.splash(30, 3), 0, "...that are gone after a moment")
  local up = false
  for _, d in ipairs(WL.splash(4, 3)) do if d[2] < 0 then up = true end end
  check(up, "...upward first")
  local s = WL.spray(10, 48, 2)
  check(#s > 0, "a whale's spout throws droplets")
  local high = 0
  for _, d in ipairs(WL.spray(15, 48, 2)) do high = math.min(high, d[2]) end
  check(high < -12, "...high up (" .. high .. " px)")
  eq(#WL.spray(48 + 40, 48, 2), 0, "...and is over after its time")
end

-- ------- a leap: out of the water in an arc and back in
do
  local cfg = Config.WATER_LIFE.leap
  local c = { cx = 5, cy = 5, t = 0, n = 40, dir = 1, renderer = {} }
  local _, _, a0 = WL._leapState(c, cfg)
  check(a0.sink > 0.9, "it starts under the surface")
  c.t = 20
  local x, _, mid = WL._leapState(c, cfg)
  check(mid.sink == 0 and mid.dy < -cfg.height + 1, "mid-leap: all out of the water, at the top of its arc")
  check(x > 5 * 16, "...carried forward")
  c.t = 40
  local _, _, a1 = WL._leapState(c, cfg)
  check(a1.sink > 0.9 and math.abs(a1.dy) < 1, "it ends back under")
end

-- ------- a whale: rises, stays up, sinks
do
  local cfg = Config.WATER_LIFE.whale
  local c = { cx = 5, cy = 5, t = 0, stay = 200, drift = 1 }
  local _, _, a = WL._whaleState(c, cfg)
  check(a.sink > 0.9, "a whale starts under")
  c.t = cfg.riseTicks + 100
  local x, _, b = WL._whaleState(c, cfg)
  eq(b.sink, 0, "...lies at the surface a while")
  check(x > 5 * 16 and x < 6 * 16, "...drifting slowly")
  c.t = cfg.riseTicks * 2 + 200
  local _, _, d = WL._whaleState(c, cfg)
  check(d.sink > 0.9, "...and sinks back under")
end

-- ------- in play
do
  local wl = WL.new(mod)
  wl:onMapEntered("ROUTE_105")
  check(wl.allowed, "outdoors: life in the water")
  wl:collectActors({}, 0, 0)
  local seen = {}
  for _ = 1, 60 * 120 do
    wl:tick()
    for _, c in ipairs(wl.creatures) do seen[c.kind] = true end
    check(wl:count("leap") <= Config.WATER_LIFE.leap.max, "never too many leaping at once")
    if wl:count("leap") > Config.WATER_LIFE.leap.max then break end
  end
  check(seen.leap, "fish leap")
  check(seen.whale, "a whale surfaces")
  check(ripples > 0, "...with ripples")
  local actors = {}
  wl:collectActors(actors, 0, 0)
  wl:onMapExited()
  eq(wl:count(), 0, "leaving the map clears the water")
  fake.mapType = function() return 8 end
  wl:onMapEntered("HOUSE")
  check(not wl.allowed, "indoors: nothing")
  fake.mapType = function() return 3 end
  optionStore.water_life = false
  wl:onMapEntered("ROUTE_105")
  check(not wl.allowed, "Water Life off: nothing")
  optionStore.water_life = nil
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("water_life_unit_test: all passed")
