-- Run: lua tests/reachability_unit_test.lua
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

local Reachability = assert(loadfile("lib/reachability.lua"))(nil)

-- A tiny map from rows of characters:
--   '.' floor   '#' wall   '~' water   'v' ledge (hop down over it, lands 2 below)
local function makeMap(rows)
  local map = { rows = rows, h = #rows, w = #rows[1] }
  function map.at(x, y)
    if y < 1 or y > map.h or x < 1 or x > map.w then return "#" end
    return rows[y]:sub(x, x)
  end
  return map
end

local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

-- A `move` like EnginePatch.reachMover builds: walls block, water needs
-- surfing (entered from the shore when `canSurf`), ledges hop one way.
local function mover(map, canSurf)
  return function(x, y, dir, state)
    local d = DELTA[dir]
    local tx, ty = x + d[1], y + d[2]
    local surfing = state and state.surfing
    local here = map.at(tx, ty)
    if not surfing and here == "v" then
      if dir == "down" and map.at(tx, ty + 1) ~= "#" then return tx, ty + 1, { surfing = map.at(tx, ty + 1) == "~" } end
      return nil
    end
    if here == "#" or here == "v" then return nil end
    if here == "~" then
      if surfing or canSurf then return tx, ty, { surfing = true } end
      return nil
    end
    return tx, ty, { surfing = false } -- floor (a dismount when surfing)
  end
end

local function reach(rows, sx, sy, canSurf, state)
  local map = makeMap(rows)
  local set, count = Reachability.build({
    startX = sx, startY = sy, startState = state or { surfing = false }, move = mover(map, canSurf),
  })
  return set, count, map
end

-- ------- key / has
eq(Reachability.key(3, 2), 2 * 65536 + 3, "key packs x and y")
check(Reachability.has({ [Reachability.key(3, 2)] = true }, 3, 2), "has finds a member")
check(not Reachability.has({}, 3, 2), "has misses a non-member")
check(not Reachability.has(nil, 3, 2), "has on a nil set is false (no restriction is the caller's call)")

-- ------- plain floor, walls split a map in two
local set, count = reach({
  "....#....",
  "....#....",
  "....#....",
}, 1, 1)
eq(count, 12, "the left room (4x3) is reachable")
check(Reachability.has(set, 4, 3), "its far corner is reachable")
check(not Reachability.has(set, 6, 1), "the room behind the wall is NOT")
check(not Reachability.has(set, 5, 1), "the wall itself is not")

-- a gap in the wall joins them
set, count = reach({
  "....#....",
  ".......  ",
  "....#....",
}, 1, 1)
check(Reachability.has(set, 9, 3), "a gap in the wall reaches the other room")

-- ------- a cave pocket sealed off
set = reach({
  "#########",
  "#...#...#",
  "#...#.X.#",
  "#########",
}, 2, 2)
check(Reachability.has(set, 4, 3) and not Reachability.has(set, 6, 2), "a sealed cave chamber is unreachable")

-- ------- water: needs Surf
local lake = {
  "..~~..",
  "..~~..",
  "..~~..",
}
set = reach(lake, 1, 1, false)
check(not Reachability.has(set, 3, 1), "without Surf the water is unreachable")
check(not Reachability.has(set, 5, 1), "...and so is the far shore it separates")
set = reach(lake, 1, 1, true)
check(Reachability.has(set, 3, 2) and Reachability.has(set, 4, 2), "with Surf the water is reachable")
check(Reachability.has(set, 6, 3), "...and the far shore across it (a dismount)")
-- already surfing: the lake is the start
set = reach(lake, 3, 2, false, { surfing = true })
check(Reachability.has(set, 4, 1) and Reachability.has(set, 1, 1),
  "a player already on the water reaches it and both shores even without the move check")

-- a waterway only reachable across a wall of land
local canal = {
  "~~~~~~",
  "######",
  "......",
}
set = reach(canal, 1, 3, true)
check(not Reachability.has(set, 1, 1), "a canal walled off from the shore is unreachable even with Surf")

-- ------- ledges are one-way
local ledge = {
  "..",
  "vv",
  "..",
  "..",
}
set = reach(ledge, 1, 1)
check(Reachability.has(set, 1, 3) and Reachability.has(set, 2, 4), "hopping down a ledge reaches the ground below")
set = reach(ledge, 1, 4)
check(not Reachability.has(set, 1, 1), "...but you can't climb back up it")

-- ------- the cap and bad input
local big = {}
for i = 1, 60 do big[i] = string.rep(".", 60) end
set, count = reach(big, 1, 1)
eq(count, 3600, "a big open map is fully filled")
local map = makeMap(big)
set, count = Reachability.build({ startX = 1, startY = 1, startState = {}, move = mover(map), maxCells = 100 })
check(count >= 100 and count < 3600, "maxCells stops a runaway fill")
check(Reachability.build({ startX = 1, startY = 1 }) == nil, "no move function -> nil")
check(Reachability.build({ move = function() end }) == nil, "no start -> nil")
set = Reachability.build({ startX = 1, startY = 1, startState = {}, move = function() error("boom") end })
eq(set and Reachability.has(set, 1, 1), true, "an erroring move never throws; the start cell is still reachable")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("reachability_unit_test: all passed")
