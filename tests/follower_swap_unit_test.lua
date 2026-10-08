-- Run: lua tests/follower_swap_unit_test.lua
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
local Swap = V.require("follower_swap")
local Cfg = V.require("config")

local function run(ctx)
  local swap = Swap.new(ctx)
  local states = {}
  while true do
    local s = swap:step()
    if not s then break end
    states[#states + 1] = s
  end
  return states
end

-- ------- a full swap: old goes in, new comes out
do
  local st = run({ hasOld = true, hasNew = true })
  check(#st > 0, "the scene runs")
  eq(st[1].phase, "recall", "it starts with the old companion going in")
  check(st[1].pose and st[1].ball ~= nil, "the arm goes up with a ball in hand on the first tick")
  eq(st[1].want, 1, "the old companion is still out while the ball is raised")
  eq(st[Cfg.SWAP.recallDelay + 1].want, 0, "then it shrinks into the player")
  local switchAt, cryAt, sends = nil, nil, 0
  for i, s in ipairs(st) do
    if s.switch then switchAt = i end
    if s.cry then cryAt = i end
    if s.phase == "send" then sends = sends + 1 end
  end
  check(switchAt ~= nil and st[switchAt].phase == "send", "the new companion takes over at the start of the send phase")
  check(st[switchAt].pose, "...and the arm goes up again")
  eq(st[switchAt].want, 0, "...with the new one still inside the ball")
  check(cryAt and cryAt > switchAt, "it cries as it comes out")
  eq(st[#st].want, 1, "it ends fully out")
  check(st[#st].ball == nil, "no ball is left hanging in the air")
  local pose = 0
  for _, s in ipairs(st) do if s.pose then pose = pose + 1 end end
  eq(pose, 2, "the player raises the ball once per phase")
  check(#st <= Cfg.SWAP.maxTicks, "within the hard cap")
end

-- ------- a recall: only the first phase
do
  local st = run({ hasOld = true, hasNew = false })
  for _, s in ipairs(st) do
    check(s.phase == "recall" and not s.switch, "a recall has no send phase") break
  end
  eq(st[#st].want, 0, "it ends inside the player")
  check(not Swap.new({ hasOld = true, hasNew = false }):hasSend(), "hasSend is false for a recall")
end

-- ------- sending out from a recall: only the second phase
do
  local st = run({ hasOld = false, hasNew = true })
  eq(st[1].phase, "send", "nothing to recall first")
  check(st[1].switch, "the new companion takes over at once")
  eq(st[1].want, 0, "...starting inside the ball")
  eq(st[#st].want, 1, "...and ends out")
end

-- ------- nothing to do
check(Swap.new({}):isFinished(), "no old and no new: finished at once")
check(Swap.new({}):step() == nil, "...and steps to nil")

-- ------- the hard cap ends a runaway scene
do
  local swap = Swap.new({ hasOld = true, hasNew = true, cfg = { poseTicks = 5000, recallDelay = 1, sendDelay = 1, ballLift = 1, ballX = 1, maxTicks = 10 } })
  local n = 0
  while swap:step() do n = n + 1 end
  eq(n, 10, "a scene stops at maxTicks")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("follower_swap_unit_test: all passed")
