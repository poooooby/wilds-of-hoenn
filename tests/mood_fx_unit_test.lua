-- Run: lua tests/mood_fx_unit_test.lua
-- lib/mood_fx.lua: which drawn effect a portrait face calls for, and what it draws.
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

local V = {}
V.require = function(name) return assert(loadfile("lib/" .. name .. ".lua"))(V) end
local MoodFx = assert(loadfile("lib/mood_fx.lua"))(V)

-- ------- which effect
eq(MoodFx.kindFor("Inspired"), "love", "loves you: hearts and sparkles")
eq(MoodFx.kindFor("Joyous"), "hearts", "joyous: hearts")
eq(MoodFx.kindFor("Happy"), "notes", "happy: music notes")
eq(MoodFx.kindFor("Determined"), "sparkles", "trusts you: sparkles")
eq(MoodFx.kindFor("Surprised"), "exclaim", "curious: a '!'")
eq(MoodFx.kindFor("Sad"), "rain", "sad: a rain cloud")
eq(MoodFx.kindFor("Crying"), "tears", "crying: tears")
eq(MoodFx.kindFor("Angry"), "anger", "angry: an anger mark")
eq(MoodFx.kindFor("Worried"), "sweat", "worried: sweat")
eq(MoodFx.kindFor("Normal"), nil, "calm: nothing")
eq(MoodFx.kindFor("Pain", "poison"), "bubbles", "poisoned: bubbles")
eq(MoodFx.kindFor("Shouting", "burn"), "flame", "burned: flames")
eq(MoodFx.kindFor("Stunned", "paralysis"), "sparks", "paralyzed: sparks")
eq(MoodFx.kindFor("Stunned", "freeze"), "snow", "frozen: snowflakes")
eq(MoodFx.kindFor("Dizzy", "sleep"), "zzz", "asleep: Zs")
eq(MoodFx.kindFor("Dizzy"), "zzz", "...a dizzy face without a status still dozes")
eq(MoodFx.kindFor("Pain"), "sweat", "hurt, no status: sweat")
eq(MoodFx.kindFor(nil), nil, "no face: nothing")

-- ------- what each draws
local kinds = { "love", "hearts", "notes", "sparkles", "exclaim", "rain", "tears", "anger", "sweat",
  "zzz", "bubbles", "flame", "sparks", "snow" }
for _, kind in ipairs(kinds) do
  local seen, ok = 0, true
  for age = 0, 200, 5 do
    for _, p in ipairs(MoodFx.particles(kind, age)) do
      seen = seen + 1
      if not MoodFx.SHAPES[p[1]] then ok = false end
      if not (p[4] >= 0 and p[4] <= 1) then ok = false end
      if math.abs(p[2]) > 16 or p[3] < -24 or p[3] > 12 then ok = false end -- stays around the head
    end
  end
  check(seen > 0 and ok, kind .. ": draws known shapes near the head, alpha 0..1")
end
eq(#MoodFx.particles("nothing", 10), 0, "an unknown effect draws nothing")
-- a rising heart climbs
local function firstHeart(age)
  for _, p in ipairs(MoodFx.particles("hearts", age)) do if p[1] == "heart" then return p end end
end
check(firstHeart(30)[3] < firstHeart(5)[3], "hearts rise")
-- every shape's rows are the same width, colours cover every number used
for name, s in pairs(MoodFx.SHAPES) do
  local w, ok = #s.rows[1], true
  for _, row in ipairs(s.rows) do
    if #row ~= w then ok = false end
    for _, v in ipairs(row) do if v ~= 0 and not s.colours[v] then ok = false end end
  end
  check(ok, "shape " .. name .. " is well formed")
end
local a = MoodFx.actor("notes", 20, 100, 50, 70, 1)
check(a.kind == "ow_mood_fx" and a.oamPriority == 1 and a.sortY == 70, "one field actor, drawn over the roofs")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("mood_fx_unit_test: all passed")
