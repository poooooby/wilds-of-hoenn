-- Run: lua tests/sweat_drop_unit_test.lua
-- lib/sweat_drop.lua: the sweat drop of a follower crouching under a roof's edge.
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

local SweatDrop = assert(loadfile("lib/sweat_drop.lua"))({})

local dy0, a0 = SweatDrop.at(0)
check(dy0 == 0 and a0 == 0, "it appears (faded in from nothing)")
local dyMid, aMid = SweatDrop.at(math.floor(SweatDrop.LIFE / 2))
check(dyMid >= 1 and aMid == 1, "then slides down its head, fully shown")
local dyEnd, aEnd = SweatDrop.at(SweatDrop.LIFE - 1)
check(dyEnd == 3 and aEnd < 0.1, "...and fades out 3 px lower")
eq(SweatDrop.at(SweatDrop.LIFE), 0, "then again from the top")
local a = SweatDrop.actor(SweatDrop.drops(10, 0.2), 40, 20, 60, 1, 0.5)
check(a.kind == "ow_sweat" and a.oamPriority == 1, "drawn over the roof it is under")
eq(#SweatDrop.drops(10, 0.1, 3), 1, "a light crouch: one drop")
eq(#SweatDrop.drops(10, 0.5, 3), 2, "harder: two")
eq(#SweatDrop.drops(10, 1, 3), 3, "squashed flat: three")
local slow = SweatDrop.drops(12, 0, 3)[1][2]
local fast = SweatDrop.drops(12, 1, 3)[1][2]
check(fast > slow, "...and the harder, the faster they run down")
local d = SweatDrop.drops(5, 1, 3, 12)
check(d[2][1] == 12 and d[1][1] == 0, "the second drop is on the other side of its head")
eq(#SweatDrop.SHAPE, 7, "a 5 x 7 drop")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("sweat_drop_unit_test: all passed")
