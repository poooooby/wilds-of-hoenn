-- Run: lua tests/shiny_sparkle_unit_test.lua
-- lib/shiny_sparkle.lua: the twinkle on a shiny Pokemon in the overworld.
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

local V = { require = function(name) return assert(loadfile("lib/" .. name .. ".lua"))(V) end }
local SS = assert(loadfile("lib/shiny_sparkle.lua"))(V)

-- one Pokemon (id 0) over a whole period
local P, frames, maxStars, quiet = SS.PERIOD, 0, 0, 0
for age = 0, P - 1 do
  local stars = SS.burst(age, 0)
  if #stars > 0 then frames = frames + 1 else quiet = quiet + 1 end
  maxStars = math.max(maxStars, #stars)
  for _, s in ipairs(stars) do
    check(SS.SHAPES[s[1]] and s[2] >= -1 and s[2] <= 1 and s[3] >= 0 and s[3] <= 1 and s[4] >= 0 and s[4] <= 1,
      "a star at age " .. age .. " is a known shape on the body, alpha 0..1")
  end
end
check(frames > 0 and frames <= SS.LIFE + (SS.COUNT - 1) * SS.STAGGER, "a short burst each period (" .. frames .. " ticks)")
check(quiet > P / 2, "...and quiet most of the time")
check(maxStars >= 2 and maxStars <= SS.COUNT, "the stars overlap a little, never more than " .. SS.COUNT)

-- the burst repeats every period; a second Pokemon is out of step
local function firstLit(id)
  for age = 0, P - 1 do if #SS.burst(age, id) > 0 then return age end end
end
local a0 = firstLit(0)
eq(#SS.burst(a0 + P, 0), #SS.burst(a0, 0), "it twinkles again a period later")
check(firstLit(1) ~= a0, "another Pokemon twinkles at its own moment")

-- a star grows then shrinks
local seen = {}
for age = a0, a0 + SS.LIFE - 1 do
  local s = SS.burst(age, 0)[1]
  if s then seen[#seen + 1] = s[1] end
end
check(seen[1] == "small" and seen[#seen] == "small", "a star starts and ends small")
local big = false
for _, s in ipairs(seen) do if s == "big" then big = true end end
check(big, "...and is big in the middle")

-- the actor: nil between bursts, one actor during one
local quietAge = a0 + SS.LIFE + SS.COUNT * SS.STAGGER
eq(#SS.burst(quietAge, 0), 0, "(a quiet moment after the burst)")
eq(SS.actor(quietAge, 0, 100, 50, 30, 10, 80, 3), nil, "between bursts there is nothing to draw")
local act = SS.actor(a0 + 2, 0, 100, 50, 30, 10, 80, 3)
check(act and act.kind == "ow_shiny_sparkle" and act.sortY == 80, "during a burst: one field actor in front of it")

-- body width
eq(SS.bodyWidth(nil), 16, "no renderer: a tile wide")
eq(SS.bodyWidth({ visualWidth = function() return 40 end }), 40, "an HGSS renderer's drawn width")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("shiny_sparkle_unit_test: all passed")
