-- Run: lua tests/follower_actions_unit_test.lua
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
  local chunk = assert(loadfile("lib/" .. name .. ".lua"))
  local value = chunk(V)
  modules[name] = value
  return value
end

local Actions = V.require("follower_actions")
local Config = V.require("config")

local CFG = {
  maxTicks = 900,
  play = { ballDist = 3, throwTicks = 10, playerPoseTicks = 8, runSpeed = 2, spinTicksPerFacing = 2,
           spins = 2, arcHeight = 12 },
  pet = { idleSpeed = 2, maxIdleTicks = 40, minIdleTicks = 10 },
  talk = { cries = 3, gap = 3, cryTimeout = 20 },
}

local function runAll(act, limit)
  local states = {}
  for _ = 1, limit or 2000 do
    local s = act:step()
    if not s then break end
    states[#states + 1] = s
  end
  return states
end

-- ------- the real config carries every knob the scenes read
for _, k in ipairs({ "maxTicks", "play", "pet", "talk" }) do
  check(Config.ACTIONS[k] ~= nil, "Config.ACTIONS." .. k .. " exists")
end

-- ------- play: throw, run out, spin, run back
do
  local act = Actions.new("play", { cfg = CFG, facing = "down", cellsAhead = 2 })
  local states = runAll(act)
  -- landPx 32 -> 16 run ticks each way; throw 10; spin 2*4*2 = 16
  eq(#states, 10 + 16 + 16 + 16, "play lasts throw + run out + spin + run back")
  check(act:isFinished(), "...and then reports finished")
  eq(act:step(), nil, "stepping a finished scene yields nothing")

  local first, last = states[1], states[#states]
  check(first.ball ~= nil, "the ball is in flight on the first tick")
  check(first.ball.y < 0, "...leaving the player's tile (behind the follower)")
  eq(states[10].ball.y, 32, "the ball lands the free distance past the follower")
  eq(states[10].ball.z, 0, "...on the ground")
  local peak = 0
  for i = 1, 10 do peak = math.max(peak, states[i].ball.z) end
  check(peak > 10, "the ball arcs above its release height")

  local out = states[10 + 16]
  eq(out.dy, 32, "the follower reaches the ball")
  eq(out.dx, 0, "...straight along the throw line")
  eq(out.facing, "down", "...facing the way it runs")
  check(out.moving, "...walking")
  check(out.ball == nil, "the ball is picked up on arrival")

  local spun, seen = {}, {}
  for i = 10 + 16 + 1, 10 + 16 + 16 do
    local s = states[i]
    check(s.moving and s.dy == 32, "spinning in place at the ball (tick " .. i .. ")")
    if not seen[s.facing] then seen[s.facing] = true spun[#spun + 1] = s.facing end
  end
  eq(table.concat(spun, ","), "down,left,up,right", "the spin turns through all four facings in order")

  local back = states[10 + 16 + 16 + 1]
  eq(back.facing, "up", "it runs back facing the player")
  eq(last.dy, 0, "the last tick is back at the start")
  eq(last.dx, 0, "...with no sideways drift")
end

-- ------- play along each direction mirrors the offset
do
  local deltas = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
  for dir, d in pairs(deltas) do
    local states = runAll(Actions.new("play", { cfg = CFG, facing = dir, cellsAhead = 1 }))
    -- landPx 16 -> 8 run ticks
    local out = states[10 + 8]
    eq(out.dx, 16 * d[1], dir .. ": x offset at the ball")
    eq(out.dy, 16 * d[2], dir .. ": y offset at the ball")
    eq(states[#states].dx, 0, dir .. ": back home (x)")
    eq(states[#states].dy, 0, dir .. ": back home (y)")
  end
end

-- ------- play with no room: the ball drops just past the follower
do
  local states = runAll(Actions.new("play", { cfg = CFG, facing = "right", cellsAhead = 0 }))
  eq(states[10].ball.x, 8, "no free cell: the ball drops half a tile out")
  local maxdx = 0
  for _, s in ipairs(states) do maxdx = math.max(maxdx, s.dx or 0) end
  eq(maxdx, 8, "...and the follower only runs that far")
end

-- ------- play never throws farther than ballDist - 1 cells past the follower
do
  local states = runAll(Actions.new("play", { cfg = CFG, facing = "down", cellsAhead = 9 }))
  eq(states[10].ball.y, 32, "the throw is capped at the configured distance")
end

-- ------- pet: a quick idle, then one cry, then it waits for the cry
do
  local cries, finished = 0, false
  local act = Actions.new("pet", { cfg = CFG, idleTicks = 60,
    playCry = function() cries = cries + 1 end, cryFinished = function() return finished end })
  local ticks, idleTicks = 0, 0
  local cryTick
  while true do
    local s = act:step()
    if not s then break end
    ticks = ticks + 1
    if s.bounce then idleTicks = idleTicks + 1 end
    if cries == 1 and not cryTick then cryTick = ticks end
    if ticks == 40 then finished = true end -- the cry ends
    if ticks > 200 then break end
  end
  eq(cries, 1, "pet cries exactly once")
  eq(idleTicks, 31, "the idle loop plays (60 ticks at 2x = 30, plus the cry's own tick)")
  eq(cryTick, 31, "the cry comes after the idle loop")
  check(act:isFinished() and ticks < 60, "the scene ends once the cry has finished")
end

-- ------- pet: an idle loop is clamped to the configured range
do
  local long = runAll(Actions.new("pet", { cfg = CFG, idleTicks = 5000,
    playCry = function() end, cryFinished = function() return true end }))
  local n = 0
  for _, s in ipairs(long) do if s.bounce then n = n + 1 end end
  eq(n, 41, "a very long idle is capped (40 ticks + the cry tick)")
  local short = runAll(Actions.new("pet", { cfg = CFG, idleTicks = 4,
    playCry = function() end, cryFinished = function() return true end }))
  n = 0
  for _, s in ipairs(short) do if s.bounce then n = n + 1 end end
  eq(n, 11, "a tiny idle is stretched to the minimum (10 ticks + the cry tick)")
end

-- ------- pet: a cry that never ends cannot hold the scene
do
  local act = Actions.new("pet", { cfg = CFG, idleTicks = 20,
    playCry = function() end, cryFinished = function() return false end })
  local states = runAll(act)
  check(act:isFinished() and #states < 80, "a stuck cry times out (" .. #states .. " ticks)")
end

-- ------- talk: three cries in succession
do
  local cries, playing, clock = 0, false, 0
  local starts = {}
  local act = Actions.new("talk", { cfg = CFG,
    playCry = function() cries = cries + 1 playing = true starts[#starts + 1] = clock end,
    cryFinished = function() return not playing end })
  local ticks = 0
  while act:step() do
    ticks = ticks + 1
    clock = ticks
    if playing and ticks % 10 == 0 then playing = false end -- each cry lasts to the next multiple of 10
    if ticks >= 300 then break end
  end
  check(ticks < 300, "talk terminates")
  eq(cries, 3, "talk cries three times")
  check(starts[2] > starts[1] and starts[3] > starts[2], "...one after the other")
  check(starts[2] - starts[1] >= 10, "...each starting only after the last finished")
  check(act:isFinished(), "...then the scene ends")
end

-- ------- talk: stuck audio times out per cry
do
  local cries = 0
  local act = Actions.new("talk", { cfg = CFG, playCry = function() cries = cries + 1 end,
    cryFinished = function() return false end })
  local states = runAll(act)
  eq(cries, 3, "three cries are still requested with stuck audio")
  check(#states <= 3 * (CFG.talk.cryTimeout + CFG.talk.gap + 2), "...within the per-cry timeouts")
end

-- ------- the hard cap ends anything
do
  local cfg = { maxTicks = 5, play = CFG.play, pet = CFG.pet, talk = CFG.talk }
  local states = runAll(Actions.new("play", { cfg = cfg, facing = "down", cellsAhead = 3 }))
  eq(#states, 5, "maxTicks cuts a long scene short")
end

-- ------- unknown action
check(Actions.new("dance", { cfg = CFG }):step() == nil, "an unknown action does nothing")

-- ------- the ball as an actor
do
  local a = Actions.ballActor({ x = 16, y = 0, z = 4 }, 80, 48, 3)
  eq(a.kind, "follower_action_ball", "ball actor kind")
  eq(a.x, 80 + 8 + 16, "ball world x = tile centre + offset")
  eq(a.y, 48 + 8, "ball world y = tile centre + offset")
  eq(a.sortY, 56.5, "it sorts by its ground position")
  check(type(a.draw) == "function", "it can draw itself")
  check(pcall(a.draw, a, 0, 0), "drawing without love.graphics is harmless")
  eq(Actions.ballActor(nil, 0, 0), nil, "no ball -> no actor")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("follower_actions_unit_test: all passed")
