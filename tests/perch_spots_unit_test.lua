-- Run: lua tests/perch_spots_unit_test.lua
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

local fake = {}
local modules = { engine_patch = fake }
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end

-- a 10 x 6 map:
--   T = tree crown (wall, draws over actors)   R = roof (same)
--   W = a plain wall (a fence: blocks, draws nothing over)
--   C = a Cut tree object on a crown-looking cell
--   ~ = water that draws over (a bridge shadow, say)   D = a door (warp)
--   S = a signpost
local MAP = {
  "TT....RRRR",
  "TT.W..RRRR",
  "....C..D..",
  "~.........",
  "..S.....S.",
  "......TT..",
}
local function cell(x, y)
  local row = MAP[y + 1]
  return row and row:sub(x + 1, x + 1) or nil
end
fake.mapBounds = function() return 10, 6 end
fake.isWall = function(x, y)
  local c = cell(x, y)
  return c == "T" or c == "R" or c == "W" or c == "C" or c == "~"
end
fake.isWater = function(x, y) return cell(x, y) == "~" end
fake.coversActors = function(x, y)
  local c = cell(x, y)
  return c == "T" or c == "R" or c == "C" or c == "~"
end
fake.objectOn = function(x, y) return cell(x, y) == "C" end
fake.isWarpCell = function(x, y) return cell(x, y) == "D" end
fake.signCells = function() return { { x = 2, y = 4 }, { x = 8, y = 4 } } end

local PerchSpots = V.require("perch_spots")
local spots = PerchSpots.build()

check(spots:at(0, 0) and spots:at(0, 0).kind == "canopy", "a tree crown is a perch")
check(spots:at(7, 0) and spots:at(7, 0).kind == "canopy", "a roof is a perch")
eq(spots:at(3, 1), nil, "a plain wall that draws nothing over actors is not")
eq(spots:at(4, 2), nil, "a Cut tree (an object) is never a perch")
eq(spots:at(0, 3), nil, "water is never a perch")
eq(spots:at(2, 2), nil, "open ground is not a perch")
check(spots:at(2, 4) and spots:at(2, 4).kind == "sign", "a signpost is a perch")
check(spots:at(8, 4) ~= nil and spots:at(8, 4).kind == "sign", "...the other one too")
eq(spots:at(7, 1), nil, "next to a door: left out (nothing sits in a doorway)")
eq(spots:at(6, 1), nil, "...diagonally too")
check(spots:at(9, 0) ~= nil, "a roof cell away from the door stays")
check(spots:at(2, 4).lift > spots:at(0, 0).lift, "a bird on a sign sits higher than on a crown")

-- picking: taken spots are skipped, accept filters
do
  local taken = {}
  for _, s in ipairs(spots.list) do if s.kind ~= "sign" then taken[s] = true end end
  local seen = {}
  for _ = 1, 30 do
    local s = spots:pick(nil, taken)
    if s then seen[s.kind] = true end
  end
  check(seen.sign and not seen.canopy, "pick skips taken spots")
  eq(spots:pick(function() return false end, nil, 10), nil, "nothing accepted -> nil")
  local near = spots:near(1, 1, 1)
  local all = true
  for _, s in ipairs(near) do if math.max(math.abs(s.x - 1), math.abs(s.y - 1)) > 1 then all = false end end
  check(#near > 0 and all, "near(): only spots within range")
end

-- without the engine pieces: no canopy perches, signs still work
do
  local saved = fake.coversActors
  fake.coversActors = nil
  local s2 = PerchSpots.build()
  eq(s2:at(0, 0), nil, "no cover check: no crown perches")
  check(s2:at(2, 4) ~= nil, "...signs still")
  fake.coversActors = saved
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("perch_spots_unit_test: all passed")
