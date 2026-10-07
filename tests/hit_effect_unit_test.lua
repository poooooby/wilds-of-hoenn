-- Run: lua tests/hit_effect_unit_test.lua
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

local E = { sheetCalls = {} }
E.fieldEffectSheet = function(name, fw, fh, frames)
  E.sheetCalls[#E.sheetCalls + 1] = { name, fw, fh, frames }
  return { image = "img", quads = { [0] = "q0", [1] = "q1", [2] = "q2" } }
end
local V = { path = "." }
function V.require(name)
  if name == "engine_patch" then return E end
  error("unexpected " .. name)
end
local HitEffect = assert(loadfile("lib/hit_effect.lua"))(V)

-- ------- the burst grows then fades
local b0, b6, b11 = HitEffect.burst(0), HitEffect.burst(6), HitEffect.burst(11)
check(b6.reach > b0.reach and b11.reach > b6.reach, "the rays fly outward")
check(b6.alpha < b0.alpha and b11.alpha < b6.alpha, "...and fade")
check(b11.length < b0.length, "...and shorten")
eq(HitEffect.burst(99).alpha, 0, "past its life it is fully faded")

-- ------- the engine's impact dust frames
eq(HitEffect.dustFrame(0), 0, "dust frame 0 first")
eq(HitEffect.dustFrame(5), 1, "...then 1")
eq(HitEffect.dustFrame(11), 2, "...then 2")
eq(HitEffect.dustFrame(12), nil, "...then nothing")
eq(HitEffect.dustFrame(-1), nil, "...and nothing before it starts")

-- ------- the actor
eq(HitEffect.actor(0, 0, HitEffect.LIFE, false), nil, "a finished effect is no actor")
local a = HitEffect.actor(64, 48, 3, true, 3, 5)
eq(a.kind, "ow_hit_effect", "it is a field actor of its own kind")
eq(a.x, 72, "centred on the tile")
eq(a.i, 90805, "own id")
check(pcall(a.draw, a, 0, 0), "drawing without love.graphics is harmless")

local calls, saved = {}, love
local function rec(name) return function(...) calls[#calls + 1] = { name, ... } end end
love = { graphics = { setColor = function() end, line = rec("line"), circle = rec("circle"), draw = rec("draw") } }
a.draw(a, 0, 0)
love = saved
local lines, draws, circles = 0, 0, 0
for _, c in ipairs(calls) do
  if c[1] == "line" then lines = lines + 1 elseif c[1] == "draw" then draws = draws + 1 elseif c[1] == "circle" then circles = circles + 1 end
end
eq(lines, 8, "a heavy hit has 8 rays")
eq(draws, 1, "the engine's dust frame is drawn")
eq(circles, 1, "with a flash at the centre")
eq(E.sheetCalls[1][1], "ground_impact_dust", "the dust is the engine's ground_impact_dust sheet")

-- a plain hit has fewer rays; no engine sheet means no dust
E.fieldEffectSheet = function() return nil end
calls = {}
local plain = HitEffect.actor(0, 0, 2, false)
love = { graphics = { setColor = function() end, line = rec("line"), circle = rec("circle"), draw = rec("draw") } }
plain.draw(plain, 0, 0)
love = saved
lines, draws = 0, 0
for _, c in ipairs(calls) do
  if c[1] == "line" then lines = lines + 1 elseif c[1] == "draw" then draws = draws + 1 end
end
eq(lines, 6, "a normal hit has 6 rays")
eq(draws, 0, "without the engine sheet there is no dust (and no error)")

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("hit_effect_unit_test: all passed")
