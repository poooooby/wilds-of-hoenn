-- Run: lua tests/ball_drop_unit_test.lua
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
local BallDrop = V.require("ball_drop")
local C = V.require("config").BALL

-- every tick's state, copied (the run refills one table)
local function run(dir)
  local r, out = BallDrop.new(dir), {}
  while true do
    local s = r:step()
    if not s then break end
    local b = s.ball
    out[#out + 1] = { recall = s.recall, poof = s.poof, z = b and b.z, alpha = b and b.alpha, burst = b and b.burst }
  end
  check(r:isFinished(), dir .. ": the run reports finished")
  check(r:step() == nil, dir .. ": nothing after the end")
  return out
end

-- ------- out: falls, bounces, pops, grows as the ball fades
do
  local st = run("out")
  eq(#st, BallDrop.length("out"), "out: lasts its length")
  check(#st <= 30, "out: quick (under half a second at 60 ticks/s)")
  local pop = BallDrop.popAt("out")
  local poofs, poofAt = 0, nil
  for i, s in ipairs(st) do if s.poof then poofs, poofAt = poofs + 1, i end end
  eq(poofs, 1, "out: one Ball Poof")
  eq(poofAt, pop, "...on the pop tick")
  for i = 1, pop - 1 do
    if st[i].recall ~= 0 then check(false, "out: still inside before the pop (tick " .. i .. ")") end
  end
  check(st[1].z > st[C.fall - 1].z, "out: the ball falls")
  check(st[1].z <= C.dropZ, "...from at most its drop height")
  eq(st[C.fall].z, 0, "out: it lands on the ground")
  local peak = 0
  for i = C.fall + 1, C.fall + C.bounce do peak = math.max(peak, st[i].z) end
  check(peak > 0 and peak <= C.bounceH, "out: one small bounce")
  check(st[pop].recall > 0 and st[pop].recall < 1, "out: it starts growing on the pop")
  check(st[pop].burst ~= nil, "...with the pop ring")
  for i = pop + 1, #st do
    if st[i].recall < st[i - 1].recall then check(false, "out: it only grows (tick " .. i .. ")") end
  end
  eq(st[#st].recall, 1, "out: fully out at the end")
  eq(st[#st].alpha, 0, "...and the ball faded away")
end

-- ------- in: drops onto it, pops, it shrinks in, the ball rests and fades
do
  local st = run("in")
  eq(#st, BallDrop.length("in"), "in: lasts its length")
  check(#st <= 30, "in: quick (under half a second at 60 ticks/s)")
  local pop = BallDrop.popAt("in")
  local poofs, poofAt = 0, nil
  for i, s in ipairs(st) do if s.poof then poofs, poofAt = poofs + 1, i end end
  eq(poofs, 1, "in: one Ball Poof")
  eq(poofAt, pop, "...when the ball reaches it")
  for i = 1, pop - 1 do
    if st[i].recall ~= 1 then check(false, "in: fully out while the ball falls (tick " .. i .. ")") end
  end
  check(st[1].z > st[pop - 1].z and st[pop - 1].z >= C.hitZ, "in: the ball falls onto it, not past it")
  check(st[pop].recall < 1, "in: it starts shrinking on contact")
  eq(st[C.fallIn + C.shrink].recall, 0, "in: fully inside once the shrink is done")
  eq(st[C.fallIn + C.shrink].z, 0, "...the ball on the ground")
  eq(st[C.fallIn + C.shrink + C.rest].alpha, 1, "in: the ball rests a moment")
  eq(st[#st].alpha, 0, "in: then it fades away")
  for i = pop + 1, #st do
    if st[i].z > st[i - 1].z then check(false, "in: the ball only settles (tick " .. i .. ")") end
  end
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("all ball_drop tests passed")
