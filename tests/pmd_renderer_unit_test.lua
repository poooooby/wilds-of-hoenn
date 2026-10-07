-- Run: lua tests/pmd_renderer_unit_test.lua
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
local V = { path = ".", mod = {} }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end
local PmdRenderer = V.require("pmd_renderer")
local Config = V.require("config")

-- ------- rowFor: baked row order is down, right, up, left
eq(PmdRenderer.rowFor("down"), 0, "down is row 0")
eq(PmdRenderer.rowFor("right"), 1, "right is row 1")
eq(PmdRenderer.rowFor("up"), 2, "up is row 2")
eq(PmdRenderer.rowFor("left"), 3, "left is row 3")
eq(PmdRenderer.rowFor(nil), 0, "unknown facing reads as down")

-- ------- frameAt: walks the per-frame tick durations, then loops
local walk = { 6, 10, 6, 10 } -- Treecko Walk
eq(PmdRenderer.frameAt(walk, 0), 0, "tick 0 is frame 0")
eq(PmdRenderer.frameAt(walk, 5), 0, "last tick of frame 0")
eq(PmdRenderer.frameAt(walk, 6), 1, "first tick of frame 1")
eq(PmdRenderer.frameAt(walk, 15), 1, "last tick of frame 1")
eq(PmdRenderer.frameAt(walk, 16), 2, "frame 2 starts at 16")
eq(PmdRenderer.frameAt(walk, 22), 3, "frame 3 starts at 22")
eq(PmdRenderer.frameAt(walk, 31), 3, "last tick of the loop")
eq(PmdRenderer.frameAt(walk, 32), 0, "the loop wraps")
eq(PmdRenderer.frameAt(walk, 32 * 7 + 7), 1, "and keeps wrapping")
eq(PmdRenderer.frameAt({ 40, 4, 2 }, 41), 1, "idle: a long hold then quick frames")
eq(PmdRenderer.frameAt({}, 10), 0, "no durations is frame 0, never an error")
eq(PmdRenderer.frameAt(walk, nil), 0, "nil clock is frame 0")

-- ------- placement: ground point onto the tile's feet spot
local entry = { ax = 15.5, ay = 19.5 }
local x, y = PmdRenderer.placement(entry, 1, 12, 100, 50)
eq(x, math.floor(108 - 15.5 + 0.5), "ground point sits on the tile's horizontal centre")
eq(y, math.floor(62 - 19.5 + 0.5), "ground point sits groundY below the tile top")
local x2 = PmdRenderer.placement(entry, 2, 12, 100, 50)
eq(x2, math.floor(108 - 31 + 0.5), "scale moves the anchor with the art")

-- ------- stepStart: Base, A, Base, B -- a step lands on a Base frame
local W = { 6, 10, 6, 10 }
eq(PmdRenderer.stepStart(W, false), 6, "an A step starts at the A frame")
eq(PmdRenderer.stepStart(W, true), 22, "a B step starts at the B frame")
eq(PmdRenderer.frameAt(W, PmdRenderer.stepStart(W, false)), 1, "A step begins on frame 1 (A)")
eq(PmdRenderer.frameAt(W, PmdRenderer.stepStart(W, true)), 3, "B step begins on frame 3 (B)")
eq(PmdRenderer.stepStart({ 8, 10, 8, 10 }, true), 26, "Charizard's walk: B step at 26")
eq(PmdRenderer.stepStart({ 5, 5, 5 }, true), 0, "a non-4-frame loop has no steps")

local function framesOf(r, ticks)
  local seen, order = {}, {}
  for _ = 1, ticks do
    local f = PmdRenderer.frameAt(W, r.clock)
    if not seen[f] then seen[f] = true order[#order + 1] = f end
    r:advance(true)
  end
  return order
end

-- ------- advance: walk while moving, idle while standing
local r = PmdRenderer.new({}, 252, false, { walk = { cols = 4, durations = W }, idle = { cols = 3 } })
eq(r.anim, "idle", "starts on the Idle loop")
r:advance(false) r:advance(false)
eq(r.clock, 2, "idle clock counts ticks")

-- step 1 = A then Base, step 2 = B then Base, step 3 = A again; each one
-- ends on the Base frame so it flows into Idle without a snap
r:advance(true)
eq(r.anim, "walk", "moving switches to Walk")
local o = framesOf(r, 16)
eq(table.concat(o, ","), "1,2", "step 1 plays A then Base")
eq(PmdRenderer.frameAt(W, r.clock), 3, "...and continuing straight on would be the B step")
r:advance(false)
eq(r.anim, "idle", "stopping returns to Idle")
eq(r.clock, 0, "and restarts it")
r:advance(true)
o = framesOf(r, 16)
eq(table.concat(o, ","), "3,0", "step 2 plays B then Base")
r:advance(false)
r:advance(true)
o = framesOf(r, 16)
eq(table.concat(o, ","), "1,2", "step 3 is an A step again")

-- continuous walking (no stop between steps) alternates by itself
r:advance(false)
r:advance(true)
o = framesOf(r, 32)
local seq = table.concat(o, ",")
check(seq == "1,2,3,0" or seq == "3,0,1,2", "two unbroken steps alternate A/B, each landing on Base (" .. seq .. ")")

Config.PMD_WALK_SPEED = 2
r:advance(false) r:advance(true)
local before = r.clock
r:advance(true)
eq(r.clock, before + 2, "PMD_WALK_SPEED scales only the walk clock")
Config.PMD_WALK_SPEED = 1

-- ------- true-size scale: global PMD_SCALE x the species' baked scale
eq(PmdRenderer.scaleOf({ scale = 1.5 }), 1, "baked species scale is ignored by default")
Config.PMD_TRUE_SIZE = true
eq(PmdRenderer.scaleOf({ scale = 1.5 }), 1.5, "species scale is used")
eq(PmdRenderer.scaleOf({}), 1, "no baked scale reads as 1")
Config.PMD_SCALE = 2
eq(PmdRenderer.scaleOf({ scale = 1.25 }), 2.5, "global PMD_SCALE multiplies it")
Config.PMD_SCALE = 1
local cw, ch = PmdRenderer.contentSize({ gutter = 2, scale = 1.5, walk = { cw = 34, ch = 28 } })
eq(cw, 45, "content width = (cell - gutters) x scale")
eq(ch, 36, "content height likewise")
eq(select(1, PmdRenderer.contentSize(nil)), 0, "no info -> 0")
Config.PMD_TRUE_SIZE = false

-- ------- idleDelay: rest on Idle's first frame before the loop plays
local f = PmdRenderer.new({}, 252, false, { walk = { cols = 4, durations = W }, idle = { cols = 3 } })
f.idleDelay = 3
f:advance(true)
f:advance(false)
eq(f.anim, "idle", "stopped -> Idle")
for _ = 1, 3 do f:advance(false) end
eq(f.clock, 0, "the clock holds at 0 for the delay")
f:advance(false)
eq(f.clock, 1, "then the Idle loop starts")
f:advance(true) f:advance(false)
for _ = 1, 2 do f:advance(false) end
eq(f.clock, 0, "the delay applies again after the next stop")
-- idleSpeed slows only the Idle loop (the follower uses 0.25 = 75% slower)
local slow = PmdRenderer.new({}, 252, false, { walk = { cols = 4, durations = W }, idle = { cols = 3 } })
slow.idleSpeed = 0.25
for _ = 1, 8 do slow:advance(false) end
eq(slow.clock, 2, "8 ticks at 0.25x advance the Idle loop by 2")
eq(PmdRenderer.frameAt({ 40, 4, 2 }, slow.clock), 0, "fractional clocks still resolve to a frame")
slow:advance(true)
slow:advance(true)
eq(slow.clock, PmdRenderer.stepStart(W, false) + 1, "Walk is not slowed (A step start + 1 tick)")
local noDelay = PmdRenderer.new({}, 252, false, { walk = { cols = 4, durations = W }, idle = { cols = 3 } })
noDelay:advance(true) noDelay:advance(false) noDelay:advance(false)
eq(noDelay.clock, 1, "no idleDelay (wild Pokemon): the loop starts at once")

-- ------- recall: the follower shrinking into the player while they surf
eq(PmdRenderer.ease(0), 0, "ease(0) = 0")
eq(PmdRenderer.ease(1), 1, "ease(1) = 1")
eq(PmdRenderer.ease(0.5), 0.5, "ease(0.5) = 0.5 (smoothstep is symmetric)")
check(PmdRenderer.ease(0.25) < 0.25 and PmdRenderer.ease(0.75) > 0.75, "ease starts and ends gently")
eq(PmdRenderer.ease(-3), 0, "ease clamps below 0")
eq(PmdRenderer.ease(7), 1, "ease clamps above 1")
do
  -- follower tile at (100, 80), player tile at (140, 60), lift 8
  local x, y, mul = PmdRenderer.recallBlend(1, 100, 80, 140, 60, 8)
  check(x == 100 and y == 80 and mul == 1, "recall 1: drawn exactly where the follower is, full size")
  x, y, mul = PmdRenderer.recallBlend(0, 100, 80, 140, 60, 8)
  check(x == 140 and y == 60 - 8 and mul == 0, "recall 0: inside the player (raised toward their body), size 0")
  x, y, mul = PmdRenderer.recallBlend(0.5, 100, 80, 140, 60, 8)
  check(x == 120 and y == 70 - 4 and mul == 0.5, "recall 0.5: halfway across, half size, half the lift")
  local x2 = PmdRenderer.recallBlend(0.25, 100, 80, 140, 60, 8)
  check(x2 > 120 and x2 < 140, "a quarter recalled is closer to the player than halfway")
end
local rr = PmdRenderer.new({}, 252, false, { walk = { cols = 4, durations = W }, idle = { cols = 3 } })
eq(rr.recall, 1, "a new renderer is fully out")
rr.recall = 0
check(pcall(function() rr:draw(0, 0, 0, 0, "down", "stand", false) end), "drawing while fully recalled never throws")

-- ------- a follower action scene: its facing and offset reach the draw call
do
  local drawn = {}
  local savedLove = love
  love = { graphics = {
    newQuad = function(qx, qy) return { qx = qx, qy = qy } end,
    draw = function(_img, quad, dx, dy) drawn[#drawn + 1] = { quad = quad, x = dx, y = dy } end,
    setColor = function() end,
  } }
  local fakeMod = { assets = { image = function() return { getDimensions = function() return 120, 104 end } end } }
  local info = { gutter = 2,
    walk = { cols = 4, cw = 30, ch = 26, durations = W, ax = 15.5, ay = 19.5 },
    idle = { cols = 3, cw = 29, ch = 31, durations = { 40, 4, 2 }, ax = 15.5, ay = 25.5 } }
  local ar = PmdRenderer.new(fakeMod, 4321, false, info)
  ar:draw(100, 50, 0, 0, "down", "stand", false)
  local base = drawn[#drawn]
  check(base ~= nil, "a normal draw reaches love.graphics.draw")
  eq(base.quad.qy, 0, "facing down uses row 0")
  ar.act = { dx = 16, dy = -8, facing = "left" }
  ar:draw(100, 50, 0, 0, "down", "stand", false)
  local moved = drawn[#drawn]
  eq(moved.quad.qy, 3 * 31, "an action's facing replaces the engine's (left = row 3)")
  eq(moved.x, base.x + 16, "an action's x offset moves the sprite")
  eq(moved.y, base.y - 8, "an action's y offset moves the sprite")
  ar.act = nil
  ar:draw(100, 50, 0, 0, "down", "stand", false)
  eq(drawn[#drawn].x, base.x, "clearing the action restores the normal draw")
  love = savedLove
end

-- ------- draw is a no-op (never an error) without art or love
check(pcall(function() r:draw(0, 0, 0, 0, "down", "stand", false) end), "draw without art/love never throws")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("pmd_renderer_unit_test: all passed")
