-- Run: lua tests/eco_air_unit_test.lua
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

-- open sea for x >= 10 (the bank at x = 10)
local ripples = 0
local fake = {
  terrainAt = function(x) if x >= 10 then return "water" end return "land" end,
  isWater = function(x) return x >= 10 end,
  startRipple = function() ripples = ripples + 1 return true end,
  playerCell = function() return { x = 0, y = 0 } end,
}
local modules = { engine_patch = fake }
local V = { path = "." }
function V.require(name)
  if modules[name] == nil then modules[name] = assert(loadfile("lib/" .. name .. ".lua"))(V) end
  return modules[name]
end
local Config = V.require("config")
local Eco = V.require("eco")
local SkyFlyers = V.require("sky_flyers")
local EcoAir = V.require("eco_air")
SkyFlyers.isRealBird = function(s) return s == 278 end -- Wingull

local planned
local sm = {
  _cellFree = function() return true end,
  sky = {
    canFly = function(_, e) return e.isFlyer end,
    clearOfPlayer = function(_, x) return x > 3 end,
    planFishing = function(_, e, tx, ty)
      planned = { from = { e.cellX, e.cellY }, to = { tx, ty } }
      return { kind = "land", mode = "swoop", fishing = true, plan = { phases = {}, i = 1 } }
    end,
  },
}
local function bird()
  local r = { bobDy = 2 }
  return { id = 3, species = 278, terrain = "water", isFlyer = true, cellX = 20, cellY = 10, px = 320, py = 160,
           state = "available", renderer = r, profile = { social = "solo" } }
end

-- ------- who fishes, and where
do
  check(EcoAir.canFish(bird(), sm), "a sea bird sitting on the water may go fishing")
  local land = bird() land.terrain = "land"
  check(not EcoAir.canFish(land, sm), "...not one on land")
  local mantine = bird() mantine.species = 226
  check(not EcoAir.canFish(mantine, sm), "...nor a Flying type that is no real bird")
  local grouped = bird() grouped.group = { leader = 3, members = { 3, 4 } }
  check(not EcoAir.canFish(grouped, sm), "...nor one leading a flock (the others would be left)")
  local under = bird()
  check(not EcoAir.canFish(under, { sky = sm.sky, underwater = true }), "...nor under the sea")
  local cfg = Config.ECO.fish
  local e = bird()
  for _ = 1, 40 do
    local x, y = EcoAir.fishingSpot(e, sm, math.random)
    local d = math.max(math.abs(x - 20), math.abs(y - 10))
    if d < cfg.range[1] or d > cfg.range[2] or x < 11 then check(false, "a spot in open water in range") break end
  end
  check(true, "it dives in open water a few tiles off")
  -- watched: the dive stays in view (a 240 x 160 view from (256, 96): cells 16.5 .. 30, 7.5 .. 15)
  sm.sky.cam, sm.sky.viewSize = { x = 256, y = 96 }, function() return 240, 160 end
  local seenOk = true
  for _ = 1, 40 do
    local x, y = EcoAir.fishingSpot(e, sm, math.random)
    if x * 16 < 256 + 8 or y * 16 < 96 + 24 or y * 16 > 96 + 160 - 24 then seenOk = false end
  end
  check(seenOk, "a bird the player can see dives where they can see it")
  sm.sky.cam = nil
  local bank = bird() bank.cellX = 11
  local bx = EcoAir.fishingSpot(bank, sm, function(a) return a end)
  check(bx == nil or bx >= 11, "...never by the bank")
end

-- ------- going fishing: the flight takes over, it moves to the spot it dives on
do
  local e = bird()
  e.ecoDue = { fish = 0 }
  local kind, st = EcoAir.choose(e, { now = 10, rng = math.random }, sm)
  eq(kind, "fish", "now and then it goes fishing")
  Eco.start(e, kind, st)
  local r0 = ripples
  Eco.step(e, { now = 11, rng = math.random }, sm)
  eq(e.eco, nil, "the flight takes over at once")
  check(e.fx and e.fx.fishing and e.fx.mode == "swoop", "...as its fx (not met while in the air)")
  eq(planned.from[1], 20, "...flown from where it sat")
  check(e.cellX == st.tx and e.cellY == st.ty, "...holding the cell it dives on")
  eq(e.renderer.bobDy, 0, "...no bob in the air")
  eq(ripples, r0 + 1, "...a ripple where it took off")
  -- a splash event in its flight: droplets and rings where it hits the water
  e.fx.plan._s = { events = { "splash" } }
  EcoAir.onFlightEvents(e)
  check(e.ecoFx and #e.ecoFx == 1 and e.rings, "a splash where it plunges in")
  local close = bird() close.cellX = 2
  close.ecoDue = { fish = 0 }
  eq(EcoAir.choose(close, { now = 10, rng = math.random }, sm), nil, "never with the player close by")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("all eco_air tests passed")
