-- Run: lua tests/forage_sparkle_unit_test.lua
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

local ForageSparkle = assert(loadfile("lib/forage_sparkle.lua"))()

-- the twinkle: fades in, then pulses forever
local g0 = ForageSparkle.glint(0)
eq(g0.alpha, 0, "it fades in from nothing")
check(ForageSparkle.glint(10).alpha > 0, "...and is visible a moment later")
local lo, hi = 1, 0
for age = 20, 20 + ForageSparkle.PERIOD do
  local g = ForageSparkle.glint(age)
  lo, hi = math.min(lo, g.alpha), math.max(hi, g.alpha)
  check(g.size >= 1.5 and g.size <= 4, "its rays stay small (" .. g.size .. ")") ; if g.size < 1.5 or g.size > 4 then break end
end
check(hi - lo > 0.4, "it twinkles (alpha " .. lo .. " to " .. hi .. ")")
check(ForageSparkle.glint(100000).alpha > 0, "it never ends on its own (the Forager takes it away)")
eq(ForageSparkle.glint(-5).alpha, 0, "a negative age is treated as new")

-- the field actor
local a = ForageSparkle.actor(160, 320, 30, 3, 1)
eq(a.kind, "ow_forage_sparkle", "an actor of its own kind")
eq(a.elevation, 3, "...at the elevation it is given")
check(a.sortY < 320 + 16, "...sorted as part of the ground (under a sprite standing there)")
check(type(a.draw) == "function", "...that can be drawn")
check(pcall(a.draw, a, 0, 0), "drawing without love.graphics does nothing and does not fail")
-- every find looks the same: nothing about the item reaches the glint
eq(ForageSparkle.actor(0, 0, 30, 3, 1).draw ~= nil, true, "the glint takes no item, so it cannot give a find away")

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("forage_sparkle_unit_test: all passed")
