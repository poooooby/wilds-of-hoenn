-- Run: lua tests/health_bar_unit_test.lua
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

local HealthBar = assert(loadfile("lib/health_bar.lua"))()
local RecallMath = assert(loadfile("lib/recall_math.lua"))()

-- ------- fill width
eq(HealthBar.fillWidth(1, true), 16, "a full bar is 16 px")
eq(HealthBar.fillWidth(0.5, true), 8, "half is 8")
eq(HealthBar.fillWidth(0.01, true), 1, "a living fighter always shows a sliver")
eq(HealthBar.fillWidth(0, false), 0, "a defeated one shows none")
eq(HealthBar.fillWidth(2, true), 16, "over-full clamps")
eq(HealthBar.fillWidth(-1, false), 0, "negative clamps")
eq(HealthBar.fillWidth("x", true), 1, "garbage reads as empty (but alive)")

-- ------- colours
local function color(r) return { HealthBar.colorFor(r) } end
check(color(1)[2] > color(1)[1], "healthy is green")
check(color(0.4)[1] > 0.9 and color(0.4)[2] > 0.7, "under half is yellow")
check(color(0.1)[1] > 0.8 and color(0.1)[2] < 0.3, "under a fifth is red")

-- ------- the actor
local a = HealthBar.actor(64, 48, 15, 30, 20, 3, 2)
eq(a.kind, "ow_health_bar", "it is a field actor of its own kind")
eq(a.x, 72, "centred over the tile")
eq(a.y, 48 + 12 - 20, "`lift` px above the ground line")
check(a.sortY > 48, "sorts in front of the sprites")
eq(a.i, 90702, "own id")
check(pcall(a.draw, a, 0, 0), "drawing without love.graphics is harmless")

local rects, saved = {}, love
love = { graphics = {
  setColor = function() end,
  rectangle = function(mode, x, y, w, h) rects[#rects + 1] = { mode, x, y, w, h } end,
} }
a.draw(a, 0, 0)
love = saved
eq(#rects, 3, "outline, track and fill")
eq(rects[3][4], 8, "the fill is half wide for half health")
local empty = HealthBar.actor(0, 0, 0, 30, 20)
rects = {}
love = { graphics = { setColor = function() end, rectangle = function(m, x, y, w, h) rects[#rects + 1] = { m, x, y, w, h } end } }
empty.draw(empty, 0, 0)
love = saved
eq(#rects, 2, "a defeated fighter draws no fill")

-- ------- recall maths (shared by both renderers)
eq(RecallMath.ease(0), 0, "ease(0)")
eq(RecallMath.ease(1), 1, "ease(1)")
eq(RecallMath.ease(0.5), 0.5, "ease(0.5)")
eq(RecallMath.ease(-3), 0, "ease clamps low")
eq(RecallMath.ease(9), 1, "ease clamps high")
local x, y, mul = RecallMath.blend(1, 100, 80, 140, 60, 8)
check(x == 100 and y == 80 and mul == 1, "recall 1: where it stands")
x, y, mul = RecallMath.blend(0, 100, 80, 140, 60, 8)
check(x == 140 and y == 60 - 8 and mul == 0, "recall 0: inside the player, lifted")

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("health_bar_unit_test: all passed")
