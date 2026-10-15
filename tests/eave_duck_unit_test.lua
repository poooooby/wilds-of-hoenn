-- Run: lua tests/eave_duck_unit_test.lua
-- lib/eave_duck.lua: how far a tall follower reaches under the covering tiles of a building
-- behind it (and never of one in front of it), and how that becomes a nudge and a squash.
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

local ED = assert(loadfile("lib/eave_duck.lua"))({})

-- a map from rows of characters: C covering tile (roof edge / eave / tree crown), W solid
-- (a wall, a trunk), . open ground
local function map(rows)
  local function at(x, y) local r = rows[y + 1] return r and r:sub(x + 1, x + 1) or "." end
  return function(x, y) return at(x, y) == "C" end, function(x, y) return at(x, y) == "W" end
end

-- a house: roof (covering) on rows 0-2, its wall on row 3, the path in front on row 4
local covers, solid = map({
  "CCCCCCCC",
  "CCCCCCCC",
  "CCCCCCCC",
  "WWWWWWWW",
  "........",
  "........",
})
-- a follower on row 4 (feet at y = 80), 64 px tall, 48 px wide, centred on x = 56
local feetRow = 4
check(ED.behind(2, 2, feetRow, covers, solid), "the house it stands in front of is behind it")
local need = ED.overlap(32, 80, 80 - 64, feetRow, covers, solid)
eq(need, 32, "its top reaches 32 px up into the eave (row 2's bottom is at y = 48, its top at 16)")
eq(ED.overlap(32, 80, 80 - 32, feetRow, covers, solid), 0, "a follower two tiles tall clears it")

-- the pieces a caller caches: the tile window, the lowest eave row in it, the px under it
local c0, c1, r0 = ED.window(32, 80, 16)
check(c0 == 2 and c1 == 4 and r0 == 1, "the art spans columns 2-4 from row 1 down")
eq(ED.lowestRow(c0, c1, r0, feetRow, covers, solid), 2, "the eave's lowest covering row is 2")
eq(ED.need(2, 16), 32, "32 px of art under row 2")
eq(ED.need(2, 20), 28, "the same row, the art 4 px lower: 28 px")
eq(ED.need(nil, 16), 0, "no eave: nothing")

-- a tree in front: its crown covers the follower's row and the one above, its trunk is south
local tc, ts = map({
  "........",
  "........",
  "...CC...",
  "...CC...",
  "...WW...",
  "........",
})
-- the follower behind the tree, feet on row 3
check(not ED.behind(3, 2, 3, tc, ts), "a tree whose trunk is south of it is in front")
eq(ED.overlap(32, 80, 48 - 48, 3, tc, ts), 0, "behind a tree it does not duck (it hides the usual way)")

-- split: a nudge first, then the squash, never below minScale
local cfg = { nudge = 8, minScale = 0.6 }
local dy, squash = ED.split(7, 40, cfg)
check(dy == 7 and squash == 0, "a small overlap: just a nudge")
dy, squash = ED.split(20, 60, cfg)
check(dy == 8 and math.abs(squash - 12 / 60) < 1e-9, "more: the nudge, then squashed for the rest")
dy, squash = ED.split(60, 70, cfg)
check(dy == 8 and math.abs(squash - 0.4) < 1e-9, "too much: never squashed below 60% of its height")
dy, squash = ED.split(0, 70, cfg)
check(dy == 0 and squash == 0, "nothing over it: standing tall")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("eave_duck_unit_test: all passed")
