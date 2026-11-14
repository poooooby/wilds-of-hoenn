-- Run: lua tests/eco_glow_unit_test.lua
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

local modules = { engine_patch = {} }
local V = { path = "." }
function V.require(name)
  if modules[name] == nil then modules[name] = assert(loadfile("lib/" .. name .. ".lua"))(V) end
  return modules[name]
end
local Config = V.require("config")
local EcoGlow = V.require("eco_glow")
local cfg = Config.ECO.glow

local function mon(at, trail)
  return { id = 4, px = 160, py = 160, facing = "left", elevation = 3,
           profile = { glow = { color = { 1, 0.9, 0.4 }, at = at or "tail", trail = trail } },
           renderer = { headLift = function() return 24 end, frontReach = function() return 10 end } }
end

-- ------- where the light sits
do
  local x, y = EcoGlow.pointOf("top", "down", 24, 0)
  check(x == 8 and y == 16 - 24 + 3, "a lure / a flame on top: just under the top of its head")
  local lx = EcoGlow.pointOf("tail", "left", 24, 10)
  local rx = EcoGlow.pointOf("tail", "right", 24, 10)
  check(lx > 8 and rx < 8, "a tail light sits behind it: right of it facing left, left of it facing right")
  local _, by = EcoGlow.pointOf("body", "down", 24, 0)
  eq(by, 4, "a body light: halfway up")
end

-- ------- it breathes, never off
do
  local lo, hi = 2, -1
  for t = 0, cfg.pulseTicks do
    local k = EcoGlow.pulse(t, 1)
    lo, hi = math.min(lo, k), math.max(hi, k)
  end
  check(lo >= 0.74 and hi <= 1.0001 and hi - lo > 0.2, ("the light breathes between %.2f and %.2f"):format(lo, hi))
end

-- ------- a firefly's trail: points while it moves at night, fading
do
  local e = mon("tail", true)
  for _ = 1, 30 do EcoGlow.tick(e, true) end
  eq(e.glowTrail, nil, "standing still: no trail")
  e.moving = true
  for _ = 1, 30 do EcoGlow.tick(e, true) end
  check(e.glowTrail and #e.glowTrail >= 5, "moving at night: a trail of light behind it")
  for _ = 1, 200 do e.px = e.px + 1 EcoGlow.tick(e, true) end
  check(#e.glowTrail <= cfg.trailMax, "...never more than trailMax points (a ring, reused)")
  e.moving = false
  for _ = 1, cfg.trailTicks + 1 do EcoGlow.tick(e, true) end
  local lit = 0
  for _, p in ipairs(e.glowTrail) do if p.age < cfg.trailTicks then lit = lit + 1 end end
  eq(lit, 0, "...and it fades away")
  local day = mon("tail", true)
  day.moving = true
  for _ = 1, 30 do EcoGlow.tick(day, false) end
  eq(day.glowTrail, nil, "by day: no trail")
  local plain = mon("top")
  plain.moving = true
  for _ = 1, 30 do EcoGlow.tick(plain, true) end
  eq(plain.glowTrail, nil, "a light with no trail leaves none")
end

-- ------- the actors: one light, dimmer and wider under the water
do
  local e = mon("top")
  local actors = {}
  EcoGlow.collect(e, actors, 10)
  check(#actors == 1 and actors[1].kind == "ow_glow" and not actors[1].under, "one light at the surface")
  local up = actors[1]
  e.renderer.act = { sink = 1 }
  actors = {}
  EcoGlow.collect(e, actors, 10)
  check(actors[1].under and actors[1].radius > up.radius and actors[1].strength < up.strength,
    "sunk under the water: still glowing, dimmer and wider")
  local f = mon("tail", true)
  f.moving = true
  for _ = 1, 12 do EcoGlow.tick(f, true) end
  actors = {}
  EcoGlow.collect(f, actors, 10)
  eq(#actors, 2, "a firefly: its light and its trail")
  local none = { id = 1, px = 0, py = 0, profile = {} }
  actors = {}
  EcoGlow.collect(none, actors, 10)
  eq(#actors, 0, "no glow in its profile: nothing")
  -- the draw runs without LOVE (headless) and with a stub
  EcoGlow._draw(up, 0, 0)
  check(true, "drawing headless is a no-op")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("eco_glow_unit_test: all passed")
