-- Run: lua tests/wild_emote_unit_test.lua
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

local modules = { engine_patch = {} }
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end
local WildEmote = V.require("wild_emote")

-- ------- the engine bubble's bounce: up, then down, resting at 0
do
  eq(WildEmote.bounce(0), 0, "starts at rest")
  eq(WildEmote.bounce(1), -5, "jumps up 5 px on the first tick")
  local top = 0
  for t = 0, 20 do top = math.min(top, WildEmote.bounce(t)) end
  eq(top, -15, "peaks 15 px up")
  eq(WildEmote.bounce(40), 0, "lands and stays put")
end

-- ------- actors
do
  local a = WildEmote.actor("anger", 0, 32, 48, 24, 3, 7)
  eq(a.emote, "anger", "the anger mark")
  eq(a.oamPriority, 1, "drawn over roofs and tree crowns, like the engine's bubble")
  eq(a.y, 48 + 16 - 24, "its bottom sits at the Pokemon's head (lift above its feet)")
  local b = WildEmote.actor("!", 1, 32, 48, 24, 3, 7)
  eq(b.y, 48 + 16 - 24 - 5, "...and bounces")
  check(type(b.draw) == "function", "drawable")
  b:draw(0, 0) -- no love.graphics in the tests: draws nothing, never errors
  check(true, "drawing without graphics does not error")
end

-- ------- the anger mark is symmetric (it reads as the same mark any way round)
do
  local s = WildEmote.ANGER
  local sym = true
  for r = 1, #s do
    for c = 1, #s[r] do
      if s[r][c] ~= s[r][#s[r] - c + 1] or s[r][c] ~= s[#s - r + 1][c] then sym = false end
    end
  end
  check(sym, "the anger mark is symmetric")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("wild_emote_unit_test: all passed")
