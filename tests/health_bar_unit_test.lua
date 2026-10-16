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
check(color(0.1)[1] > 0.8 and color(0.1)[2] < 0.4, "under a fifth is red")

-- ------- the actor
local a = HealthBar.actor(64, 48, 15, 30, 20, 3, 2)
eq(a.kind, "ow_health_bar", "it is a field actor of its own kind")
eq(a.x, 72, "centred over the tile")
eq(a.y, 48 + 12 - 20, "`lift` px above the ground line")
check(a.sortY > 48, "sorts in front of the sprites")
eq(a.i, 90702, "own id")
check(pcall(a.draw, a, 0, 0), "drawing without love.graphics is harmless")

-- every pixel drawn exactly once, all at the bar's alpha (translucent rects must not overlap)
local function paint(actor)
  local px, alphas, n = {}, {}, 0
  local saved = love
  love = { graphics = {
    setColor = function(_, _, _, al) alphas[#alphas + 1] = al end,
    rectangle = function(_, x, y, w, h)
      n = n + 1
      for yy = y, y + h - 1 do for xx = x, x + w - 1 do
        local k = xx .. "," .. yy
        px[k] = (px[k] or 0) + 1
      end end
    end,
  } }
  actor.draw(actor, 0, 0)
  love = saved
  return px, alphas, n
end
local px, alphas = paint(a)
local cells, twice = 0, 0
for _, c in pairs(px) do cells = cells + 1 if c > 1 then twice = twice + 1 end end
eq(cells, 18 * 5, "the bar covers its outline box (18 x 5)")
eq(twice, 0, "no pixel is drawn twice (would darken at 80% alpha)")
local allAlpha = true
for i = 1, #alphas - 1 do if alphas[i] ~= HealthBar.ALPHA then allAlpha = false end end
check(allAlpha and HealthBar.ALPHA == 0.8, "everything is drawn 80% opaque")
eq(alphas[#alphas], 1, "the colour is reset afterwards")
local empty = HealthBar.actor(0, 0, 0, 30, 20)
local epx = paint(empty)
cells, twice = 0, 0
for _, c in pairs(epx) do cells = cells + 1 if c > 1 then twice = twice + 1 end end
check(cells == 90 and twice == 0, "a defeated fighter: the empty band fills the bar, once")
local p = HealthBar.paletteFor(1)
check(p.light[2] > p.dark[2], "the middle row is brighter than its shade")

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
