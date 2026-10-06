-- Run: lua tests/behavior_unit_test.lua
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

local fakeEngine = {}
local modules = {}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  if name == "engine_patch" then
    modules[name] = fakeEngine
    return fakeEngine
  end
  local chunk = assert(loadfile("lib/" .. name .. ".lua"))
  local value = chunk(V)
  modules[name] = value
  return value
end

-- An open 5x5 field, all land, nothing blocking.
fakeEngine.canEnter = function(_game, tx, ty, _opts)
  return tx >= 0 and tx < 5 and ty >= 0 and ty < 5
end
fakeEngine.isWater = function(_tx, _ty) return false end

local Behavior = V.require("behavior")

-- ------- pick() respects an injected rng
eq(Behavior.pick(function() return 0.0 end), Behavior.IDLE, "pick(0.0) -> idle")
eq(Behavior.pick(function() return 0.99 end), Behavior.ROAM, "pick(0.99) -> roam")

-- ------- a deterministic rng sequence drives tick() predictably
local function seq(values)
  local i = 0
  return function()
    i = i + 1
    return values[i] or values[#values]
  end
end

-- ------- idle: never moves, only turns
local idle = {
  cellX = 2, cellY = 2, facing = "down", behavior = Behavior.IDLE, terrain = "land",
  elevation = 3, moving = false, ticksUntilAction = 0,
}
-- rng draws: [1] jitter for next ticksUntilAction, [2] facing pick (0.5 -> dir index 3 = "left")
Behavior.tick(idle, {}, seq({ 0.1, 0.5 }))
eq(idle.moving, false, "idle never starts moving")
eq(idle.cellX, 2, "idle never changes cell (x)")
eq(idle.cellY, 2, "idle never changes cell (y)")
check(idle.ticksUntilAction > 0, "idle re-arms its action timer")

-- ------- roam: moves toward an open cell and completes the step
local roam = {
  cellX = 2, cellY = 2, facing = "down", behavior = Behavior.ROAM, terrain = "land",
  elevation = 3, moving = false, ticksUntilAction = 0, px = 32, py = 32,
}
-- rng draws: [1] jitter, [2] dir pick 0.26 -> index 2 = "down" (up,down,left,right)
Behavior.tick(roam, {}, seq({ 0.1, 0.26 }))
check(roam.moving == true, "roam starts a move onto an open cell")
eq(roam.facing, "down", "roam faces the direction it chose")
eq(roam.targetX, 2, "roam target cell x unchanged (moved in y)")
eq(roam.targetY, 3, "roam target cell y advanced")

-- Advance the move to completion.
local advanced = 0
while roam.moving and advanced < 100 do
  Behavior.tick(roam, {}, seq({ 0 }))
  advanced = advanced + 1
end
check(advanced < 100, "roam's move actually finishes within stepFrames ticks")
eq(roam.cellX, 2, "roam lands on the target cell (x)")
eq(roam.cellY, 3, "roam lands on the target cell (y)")
eq(roam.moving, false, "roam clears moving once it lands")

-- ------- roam never leaves its map edge or its terrain
fakeEngine.canEnter = function(_game, tx, ty, _opts) return tx >= 0 and tx < 5 and ty >= 0 and ty < 5 end
local edge = {
  cellX = 0, cellY = 0, facing = "down", behavior = Behavior.ROAM, terrain = "land",
  elevation = 3, moving = false, ticksUntilAction = 0, px = 0, py = 0,
}
-- dir pick -> index 1 = "up" (delta 0,-1), which would leave the 5x5 field
Behavior.tick(edge, {}, seq({ 0.1, 0.0 }))
check(edge.moving == false, "roam refuses a step that would leave the map")
eq(edge.cellX, 0, "blocked roam never changes cell (x)")
eq(edge.cellY, 0, "blocked roam never changes cell (y)")

-- A water spawn refuses to step onto land, even when canEnter allows it.
fakeEngine.canEnter = function(_game, _tx, _ty, _opts) return true end
fakeEngine.isWater = function(tx, ty) return tx < 3 end -- land at x>=3
local waterMon = {
  cellX = 2, cellY = 2, facing = "down", behavior = Behavior.ROAM, terrain = "water",
  elevation = 3, moving = false, ticksUntilAction = 0, px = 32, py = 32,
}
-- dir pick index 4 = "right" (delta 1,0) steps from x=2 (water) to x=3 (land)
Behavior.tick(waterMon, {}, seq({ 0.1, 0.99 }))
check(waterMon.moving == false, "a water spawn refuses a step onto land")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("behavior_unit_test: all passed")
