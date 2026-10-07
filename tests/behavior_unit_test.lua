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

-- An open 5x5 field, all land encounter tiles, nothing blocking.
fakeEngine.canEnter = function(_game, tx, ty, _opts)
  return tx >= 0 and tx < 5 and ty >= 0 and ty < 5
end
fakeEngine.terrainAt = function(_tx, _ty) return "land" end

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

-- ------- roam never leaves its map edge
fakeEngine.canEnter = function(_game, tx, ty, _opts) return tx >= 0 and tx < 5 and ty >= 0 and ty < 5 end
fakeEngine.terrainAt = function(_tx, _ty) return "land" end
local edge = {
  cellX = 0, cellY = 0, facing = "down", behavior = Behavior.ROAM, terrain = "land",
  elevation = 3, moving = false, ticksUntilAction = 0, px = 0, py = 0,
}
-- dir pick -> index 1 = "up" (delta 0,-1), which would leave the 5x5 field
Behavior.tick(edge, {}, seq({ 0.1, 0.0 }))
check(edge.moving == false, "roam refuses a step that would leave the map")
eq(edge.cellX, 0, "blocked roam never changes cell (x)")
eq(edge.cellY, 0, "blocked roam never changes cell (y)")

-- ------- a water spawn refuses to step onto land, even when canEnter allows it
fakeEngine.canEnter = function(_game, _tx, _ty, _opts) return true end
fakeEngine.terrainAt = function(tx, _ty) return tx < 3 and "water" or "land" end -- land at x>=3
local waterMon = {
  cellX = 2, cellY = 2, facing = "down", behavior = Behavior.ROAM, terrain = "water",
  elevation = 3, moving = false, ticksUntilAction = 0, px = 32, py = 32,
}
-- dir pick index 4 = "right" (delta 1,0) steps from x=2 (water) to x=3 (land)
Behavior.tick(waterMon, {}, seq({ 0.1, 0.99 }))
check(waterMon.moving == false, "a water spawn refuses a step onto land")

-- ------- regression: a roaming land spawn refuses a walkable tile that is
-- NOT an encounter tile at all (a path, a doodad, anywhere outside its own
-- grass patch) -- the actual bug report this guards against: canEnter and
-- "not water" both say yes, but terrainAt says the tile has no encounters,
-- so the step must still be refused.
fakeEngine.canEnter = function(_game, _tx, _ty, _opts) return true end -- fully walkable
fakeEngine.terrainAt = function(tx, _ty) return tx < 3 and "land" or nil end -- a path at x>=3
local pathMon = {
  cellX = 2, cellY = 2, facing = "down", behavior = Behavior.ROAM, terrain = "land",
  elevation = 3, moving = false, ticksUntilAction = 0, px = 32, py = 32,
}
-- dir pick index 4 = "right": steps from x=2 (land) onto x=3 (a walkable
-- non-water path with no encounters) -- must be refused even though it's
-- neither blocked nor water.
Behavior.tick(pathMon, {}, seq({ 0.1, 0.99 }))
check(pathMon.moving == false, "a land spawn refuses a walkable tile with no encounters (a path)")
eq(pathMon.cellX, 2, "it never leaves its own grass cell (x)")

-- A step that stays within the SAME terrain kind is still allowed.
pathMon.ticksUntilAction = 0
-- dir pick index 1 = "up" (delta 0,-1): y decreases, x stays 2 (still "land")
Behavior.tick(pathMon, {}, seq({ 0.1, 0.0 }))
check(pathMon.moving == true, "a step that stays on the same encounter terrain is still allowed")

-- ------- regression: terrainAt is checked BEFORE canEnter, not after --
-- canEnter is the call that reaches the real engine's Collision.canEnter,
-- which always resolves occupancy through Objects.blocks(tx, ty, nil,
-- elevation), the exact nil-exceptLocalId shape main.lua's `blocks` hook
-- uses to detect a real player bump (see lib/engine_patch.lua's
-- isProbingCanEnter). That reentrancy is already guarded regardless of
-- call order, but a terrain-invalid direction should never reach the
-- engine's collision system at all -- there's no reason to make that call
-- for a step this Pokemon could never actually take.
local canEnterCalls = 0
fakeEngine.canEnter = function(_game, _tx, _ty, _opts) canEnterCalls = canEnterCalls + 1 return true end
fakeEngine.terrainAt = function(_tx, _ty) return nil end -- every direction is terrain-invalid
local terrainMon = {
  cellX = 2, cellY = 2, facing = "down", behavior = Behavior.ROAM, terrain = "land",
  elevation = 3, moving = false, ticksUntilAction = 0, px = 32, py = 32,
}
Behavior.tick(terrainMon, {}, seq({ 0.1, 0.0 }))
eq(canEnterCalls, 0, "canEnter is never called for a direction terrainAt already rejects")
check(terrainMon.moving == false, "the step is still refused")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("behavior_unit_test: all passed")
