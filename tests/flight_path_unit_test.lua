-- Run: lua tests/flight_path_unit_test.lua
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
local function near(a, b, msg, tol)
  check(a and math.abs(a - b) <= (tol or 1e-6), string.format("%s (got %s expected %s)", msg, tostring(a), tostring(b)))
end

local modules = {}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end

local FlightPath = V.require("flight_path")
local Config = V.require("config")

-- ------- the look by height: higher = bigger, faster, blurrier, fainter
do
  local low, mid, high = FlightPath.look(0), FlightPath.look(0.5), FlightPath.look(1)
  eq(low.scale, 1, "low: drawn at its own size")
  eq(low.parallax, 1, "low: moves with the ground")
  eq(low.blur, 0, "low: in focus")
  check(mid.scale > low.scale and high.scale > mid.scale, "higher is bigger (closer to the camera)")
  check(high.parallax > mid.parallax and mid.parallax > 1, "higher slides faster than the ground")
  check(high.blur > mid.blur and mid.blur > 0, "higher is more out of focus")
  check(high.alpha < mid.alpha and mid.alpha < 1, "higher is fainter")
  near(FlightPath.look(0.25).scale, (low.scale + mid.scale) / 2, "between layers: interpolated")
  eq(FlightPath.look(5).scale, high.scale, "above 1: clamped to high")
  eq(FlightPath.look(-1).scale, low.scale, "below 0: clamped to low")
end

-- ------- perspective about the view's centre
do
  local sx, sy = FlightPath.toScreen(100, 60, 1, 20, 10, 240, 160)
  eq(sx, 80, "parallax 1: screen = world - camera (x)")
  eq(sy, 50, "parallax 1: screen = world - camera (y)")
  local cx, cy = FlightPath.toScreen(20 + 120, 10 + 80, 1.6, 20, 10, 240, 160)
  check(cx == 120 and cy == 80, "a bird over the view's centre stays at the centre at any height")
  local hx = FlightPath.toScreen(20 + 200, 0, 1.6, 20, 10, 240, 160)
  check(hx > 200, "a high bird off the centre is pushed outward (perspective)")
  local wx, wy = FlightPath.fromScreen(33, 77, 1.6, 400, 300, 240, 160)
  local bx, by = FlightPath.toScreen(wx, wy, 1.6, 400, 300, 240, 160)
  near(bx, 33, "fromScreen / toScreen round trip (x)")
  near(by, 77, "fromScreen / toScreen round trip (y)")
  -- the camera moving 10 px slides a high bird 16 px on screen, the ground 10
  local a = FlightPath.toScreen(300, 0, 1.6, 100, 0, 240, 160)
  local b = FlightPath.toScreen(300, 0, 1.6, 110, 0, 240, 160)
  near(a - b, 16, "parallax 1.6: the view scrolling 10 px moves it 16 px")
end

-- ------- facing from movement
eq(FlightPath.facing(5, 1), "right", "mostly right -> right")
eq(FlightPath.facing(-5, 2), "left", "mostly left -> left")
eq(FlightPath.facing(1, -6), "up", "mostly up -> up")
eq(FlightPath.facing(0, 3), "down", "down -> down")
eq(FlightPath.facing(0, 0), nil, "not moving -> nil")

-- ------- edge points sit outside the view
do
  for _, side in ipairs({ "left", "right", "top", "bottom" }) do
    local x, y = FlightPath.edgePoint(240, 160, 40, function(a, b) return a end, side)
    local out = x < 0 or x > 240 or y < 0 or y > 160
    check(out, "edge point on the " .. side .. " is off screen")
  end
  eq(FlightPath.OPPOSITE.left, "right", "a passer leaves on the other side")
end

-- ------- a fly phase: from -> to, height eased, ends exactly on its target
do
  local plan = FlightPath.plan({
    { type = "fly", from = { x = 0, y = 0, h = 1 }, to = { x = 160, y = 32, h = 0 }, n = 40, curve = 12,
      event = "start" },
  })
  local first = FlightPath.step(plan)
  eq(first.events[1], "start", "a phase's event is reported on its first tick")
  check(first.flapping, "flying: wings beating")
  check(first.h > 0.9, "starts high")
  eq(first.facing, "right", "faces the way it flies")
  local s = first
  local steps = 1
  while not FlightPath.done(plan) do s = FlightPath.step(plan) steps = steps + 1 end
  eq(steps, 40, "runs its n ticks")
  near(s.x, 160, "ends on its target (x)", 1e-6)
  near(s.y, 32, "ends on its target (y)", 1e-6)
  near(s.h, 0, "ends on the ground", 1e-6)
  eq(FlightPath.step(plan), nil, "a finished plan steps to nil")
end

-- ------- a sit: folded wings, fidgets (turn / hop) now and then, never flapping
do
  local kinds, k = { 1, 2, 3 }, 0
  local function rng(a, b)
    if a == 1 and b == 3 then k = k % 3 + 1 return kinds[k] end -- turn, hop, both, ...
    if a == 1 and b == 4 then return (k % 4) + 1 end           -- a new facing
    return a
  end
  local plan = FlightPath.plan({ { type = "sit", at = { x = 16, y = 16, lift = 6 }, n = 200, facing = "left", fidget = { 40, 40 } } }, rng)
  local turned, hopped, flapped = false, false, false
  local last = "left"
  for _ = 1, 200 do
    local s = FlightPath.step(plan)
    if s.flapping then flapped = true end
    if s.facing ~= last then turned = true last = s.facing end
    if (s.hop or 0) > 0 then hopped = true end
    eq(s.lift, 6, "sits on its perch's lift") if s.lift ~= 6 then break end
    if not s.sitting then check(false, "sitting the whole phase") break end
  end
  check(turned, "a perched bird turns now and then")
  check(hopped, "...and makes little hops")
  check(not flapped, "...but never flaps its wings")
  check(FlightPath.done(plan), "the sit ends after n ticks")
end

-- ------- scaring it off: the rest of the plan replaced, starting now
do
  local plan = FlightPath.plan({
    { type = "sit", at = { x = 0, y = 0 }, n = 1000 },
    { type = "fly", from = { x = 0, y = 0, h = 0 }, to = { x = 99, y = 0, h = 1 }, n = 50 },
  })
  FlightPath.step(plan)
  FlightPath.replaceRest(plan, { { type = "fly", from = { x = 0, y = 0, h = 0 }, to = { x = -50, y = 0, h = 1 }, n = 5 } }, true)
  local s = FlightPath.step(plan)
  check(s.flapping and not s.sitting, "scared: it takes off at once")
  eq(s.facing, "left", "...the new way")
  for _ = 1, 4 do FlightPath.step(plan) end
  check(FlightPath.done(plan), "...and the old take-off is gone")
end

-- ------- a dive: into the water, under, back out
do
  local at = { x = 32, y = 48 }
  local plan = FlightPath.plan({
    { type = "sink", at = at, n = 4, event = "splash" },
    { type = "under", at = at, n = 3 },
    { type = "rise", at = at, n = 4, event = "splash" },
  })
  local s = FlightPath.step(plan)
  eq(s.events[1], "splash", "splash on going in")
  check(s.sink > 0 and s.sink < 1, "sinking")
  for _ = 1, 3 do s = FlightPath.step(plan) end
  near(s.sink, 1, "under the line at the end of the sink")
  s = FlightPath.step(plan)
  check(s.hidden, "hidden while under")
  FlightPath.step(plan) FlightPath.step(plan)
  s = FlightPath.step(plan)
  eq(s.events[1], "splash", "splash on coming out")
  for _ = 1, 3 do s = FlightPath.step(plan) end
  near(s.sink, 0, "fully out again")
end

-- ------- a hop off a perch: an arc down to the ground cell
do
  local plan = FlightPath.plan({ { type = "hop", from = { x = 0, y = 0, lift = 6 }, to = { x = 16, y = 16, lift = 0 }, n = 10, height = 8 } })
  local top = 0
  local s
  for _ = 1, 10 do s = FlightPath.step(plan) top = math.max(top, s.hop or 0) end
  check(top > 6, "the hop arcs up")
  near(s.x, 16, "lands on the cell (x)")
  near(s.lift, 0, "...on the ground")
end

check(Config.FLYERS.sharpBelow < Config.FLYERS.sharpAbove, "the crossfade band is ordered")

-- ------- a swimmer's wave: side to side along the way, still ending on its target
do
  local plan = FlightPath.plan({ { type = "fly", from = { x = 0, y = 0, h = 0 }, to = { x = 100, y = 0, h = 0 }, n = 40,
    wave = { 3, 2 } } })
  local maxOff, s = 0, nil
  for _ = 1, 40 do s = FlightPath.step(plan) maxOff = math.max(maxOff, math.abs(s.y)) end
  check(maxOff > 2 and maxOff <= 3.01, "it wiggles about 3 px off the line")
  check(math.abs(s.x - 100) < 1e-6 and math.abs(s.y) < 1e-6, "...and still ends on its target")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("flight_path_unit_test: all passed")
