-- Run: lua tests/eco_water_unit_test.lua
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

-- a lake: water everywhere at x 0..9, y 0..8 (y 9 is the bank), land beyond
local ripples = {}
local fake = {
  terrainAt = function(x, y) if x >= 0 and x <= 9 and y >= 0 and y <= 9 then return "water" end return "land" end,
  isWater = function(x, y) return x >= 0 and x <= 9 and y >= 0 and y <= 9 end,
  startRipple = function(x, y) ripples[#ripples + 1] = { x, y } end,
  playerCell = function() return { x = 20, y = 20 } end,
}
local modules = { engine_patch = fake }
local V = { path = "." }
function V.require(name)
  if modules[name] == nil then modules[name] = assert(loadfile("lib/" .. name .. ".lua"))(V) end
  return modules[name]
end
local Config = V.require("config")
local Eco = V.require("eco")
local EcoWater = V.require("eco_water")
local SpriteSource = V.require("sprite_source")

local function fish(x, y, water)
  return { id = 1, terrain = "water", cellX = x, cellY = y, px = x * 16, py = y * 16, facing = "right",
           state = "available", profile = { water = water or "leaper" },
           renderer = { isPmd = true, presentation = "swimming", swimming = true, bobDy = 1,
                        advanceAs = function(r, a) r.lastAnim = a end, advance = function() end,
                        headLift = function() return 20 end } }
end
local sm = { occupiedBy = function() return nil end, dives = {} }
function sm:startDive(e) self.dives[#self.dives + 1] = e end

-- ------- where a leap lands
do
  local e = fish(4, 4)
  local x, y = EcoWater._landingCell(e, sm, 1)
  check(x == 5 and y == 4, "open water ahead: it lands a tile on")
  e.cellX = 9
  x, y = EcoWater._landingCell(e, sm, 1)
  check(x == 9 and y == 4, "the shore ahead: back where it went in")
  e.cellX, e.cellY = 4, 8
  x, y = EcoWater._landingCell(e, sm, 1)
  check(x == 5 and y == 8, "the row above the bank is still open water (y 9 is water too)")
  e.cellY = 9
  x, y = EcoWater._landingCell(e, sm, 1)
  check(x == 4 and y == 9, "never onto the last water row before a bank")
  e.cellY = 4
  local busy = { occupiedBy = function(_, xx, yy) if xx == 5 and yy == 4 then return {} end end }
  x = EcoWater._landingCell(e, busy, 1)
  eq(x, 4, "another Pokemon there: back where it went in")
end

-- ------- a whole leap: airborne with its land art, untouchable, splashes, lands a tile on
do
  ripples = {}
  local e = fish(4, 4)
  local s = EcoWater.leapState(e, sm, function(a) return a end)
  check(Eco.start(e, "leap", s), "a leap starts")
  check(not Eco.touchable(e), "...in the air it cannot be met")
  local peak, sawLand = 0, false
  for _ = 1, 60 do
    if not e.eco then break end
    Eco.step(e, {}, sm)
    local r = e.renderer
    if r.act then peak = math.min(peak, r.act.dy or 0) end
    if r.presentation == SpriteSource.PRESENTATION_LAND and r.swimming == false then sawLand = true end
  end
  eq(e.eco, nil, "the leap ends")
  check(peak <= -Config.ECO.water.leap.pmdHeight + 0.5, "it rose out of the water (" .. peak .. " px)")
  check(sawLand, "...drawn whole with its land art while in the air")
  eq(e.renderer.presentation, "swimming", "back in the water: its swimming art again")
  eq(e.renderer.swimming, true, "...the waterline crop back on")
  eq(e.renderer.act, nil, "...no leftover offset")
  eq(e.cellX, 5, "it landed a tile on")
  eq(e.px, 80, "...and is drawn there")
  eq(#ripples, 2, "a ripple where it left and where it landed")
  check(e.ecoFx and #e.ecoFx == 2, "two splashes of droplets")
  eq(e.renderer.lastAnim, "hop", "PMD art plays its Hop in the air")
  for _ = 1, 30 do EcoWater.ageFx(e) end
  eq(e.ecoFx, nil, "the droplets are gone after a while")
end

-- ------- cut short (the player touched it, the option went off): put back at once
do
  local e = fish(4, 4)
  Eco.start(e, "leap", EcoWater.leapState(e, sm, function(a) return a end))
  for _ = 1, 10 do Eco.step(e, {}, sm) end
  Eco.abort(e, sm)
  eq(e.renderer.presentation, "swimming", "aborted: its swimming art back")
  eq(e.px, 64, "...drawn on its own cell")
  eq(e.cellX, 4, "...which it never left")
  eq(e.renderer.act, nil, "...no leftover offset")
end

-- ------- a whale blows, then sounds
do
  local e = fish(4, 4, "whale")
  local s = EcoWater.spoutState(e, function(a) return a end)
  Eco.start(e, "spout", s)
  local sprays = 0
  for _ = 1, s.n + 5 do
    if not e.eco then break end
    local before = e.ecoFx and #e.ecoFx or 0
    Eco.step(e, {}, sm)
    if (e.ecoFx and #e.ecoFx or 0) > before then sprays = sprays + 1 end
  end
  check(sprays >= 1, "a whale blows a spout (" .. sprays .. ")")
  eq(sm.dives[#sm.dives], e, "...then sounds: it dives")
  check(Eco.touchable(e), "it could be met the whole time it lay at the surface")
end

-- ------- what a water Pokemon chooses, and when
do
  local rng = function(a) return a end
  local e = fish(4, 4)
  local ctx = { now = 0, rng = rng, player = { x = 20, y = 20 } }
  eq(EcoWater.choose(e, ctx, sm), nil, "the first look only sets the leaper's timer")
  ctx.now = Config.ECO.water.leap.every[1]
  eq(EcoWater.choose(e, ctx, sm), "leap", "...then it leaps")
  ctx.now = ctx.now + 10
  eq(EcoWater.choose(e, ctx, sm), nil, "...not again straight away")
  local near = fish(4, 4)
  near.ecoDue = { leap = 0 }
  eq(EcoWater.choose(near, { now = 999, rng = rng, player = { x = 5, y = 4 } }, sm), nil,
    "never right beside the player")
  local drifter = fish(4, 4, "drifter")
  drifter.ecoDue = { leap = 0, spout = 0 }
  eq(EcoWater.choose(drifter, { now = 999, rng = rng, player = { x = 20, y = 20 } }, sm), nil, "a drifter neither leaps nor spouts")
  local land = fish(4, 4)
  land.terrain = "land"
  land.ecoDue = { leap = 0 }
  eq(EcoWater.choose(land, { now = 999, rng = rng }, sm), nil, "a land Pokemon does no water things")
  local deep = fish(4, 4)
  deep.ecoDue = { leap = 0 }
  eq(EcoWater.choose(deep, { now = 999, rng = rng }, { underwater = true }), nil, "nothing leaps under the sea")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("eco_water_unit_test: all passed")
