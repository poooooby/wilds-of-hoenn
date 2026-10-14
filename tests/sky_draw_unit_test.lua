-- Run: lua tests/sky_draw_unit_test.lua
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

local modules = {}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end

local SkyDraw = V.require("sky_draw")
local Config = V.require("config")

-- ------- sharp vs blurred, and the crossfade between
do
  local lo, hi = Config.FLYERS.sharpBelow, Config.FLYERS.sharpAbove
  check(not SkyDraw.blurred(0), "on the ground: drawn sharp")
  check(SkyDraw.blurred(1), "high up: drawn blurred")
  local s, b = SkyDraw.mix(0)
  check(s == 1 and b == 0, "low: only the sharp sprite")
  s, b = SkyDraw.mix(1)
  check(s == 0 and b == 1, "high: only the blurred one")
  s, b = SkyDraw.mix((lo + hi) / 2)
  check(math.abs(s - 0.5) < 1e-9 and math.abs(b - 0.5) < 1e-9, "in between: half and half (no pop)")
end

-- ------- no love.graphics (a test, a headless run): prepare draws nothing, fails soft
check(SkyDraw.prepare({ renderer = { draw = function() end } }) == false, "no graphics: prepare does nothing")

-- ------- the actors one bird gives
do
  local drawn = 0
  local renderer = { draw = function() drawn = drawn + 1 end }
  local low = { id = 1, renderer = renderer, x = 160, y = 96, h = 0, facing = "left", width = 20 }
  local actors = {}
  SkyDraw.push(actors, low, 0, 0, 240, 160)
  local sky, shadow
  for _, a in ipairs(actors) do
    if a.kind == "sky_mon" then sky = a end
    if a.kind == "sky_shadow" then shadow = a end
  end
  check(sky ~= nil, "a low bird: one sharp sprite")
  eq(sky and sky.priority, 1, "...drawn after the map's upper layer (roofs, tree crowns)")
  check(sky and sky.fixedPriority, "...at a fixed priority")
  eq(shadow, nil, "...and no ground shadow")
  sky:draw(0, 0)
  eq(drawn, 1, "the sharp sprite draws through the bird's own renderer (gen3-hd-sprites sizes it)")
  eq(renderer.act, nil, "...and leaves the renderer's act as it found it")

  local high = { id = 2, renderer = renderer, x = 160, y = 96, h = 1 }
  actors = {}
  SkyDraw.push(actors, high, 0, 0, 240, 160)
  local kinds = {}
  for _, a in ipairs(actors) do kinds[a.kind] = true end
  check(not kinds.sky_mon, "a high bird: no sharp sprite")
  check(not kinds.sky_mon_far, "...and no blurred one before its canvas is prepared")

  actors = {}
  SkyDraw.push(actors, { id = 3, renderer = renderer, x = 0, y = 0, h = 0, hidden = true }, 0, 0, 240, 160)
  eq(#actors, 0, "a hidden bird (under water) draws nothing")

end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("sky_draw_unit_test: all passed")
