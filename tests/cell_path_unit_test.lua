-- Run: lua tests/cell_path_unit_test.lua
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

local CellPath = assert(loadfile("lib/cell_path.lua"))()

-- a wall at x = 3 with a gap at y = 5
local function free(x, y)
  if x < 0 or x > 8 or y < 0 or y > 8 then return false end
  if x == 3 and y ~= 5 then return false end
  return true
end

local res = CellPath.search(1, 1, { free = free, maxDepth = 20 })
local path = CellPath.pathTo(res, 5, 1)
check(path ~= nil, "a cell behind the wall is reached")
eq(#path, 12, "...by walking through the gap (4 down, 4 across, 4 back up)")
local last = path[#path]
check(last[1] == 5 and last[2] == 1, "...and the path ends where asked")
local wentThroughGap = false
for _, c in ipairs(path) do
  check(free(c[1], c[2]), "every step is on an open cell")
  if c[1] == 3 and c[2] == 5 then wentThroughGap = true end
end
check(wentThroughGap, "it used the gap")
for i = 2, #path do
  local d = math.abs(path[i][1] - path[i - 1][1]) + math.abs(path[i][2] - path[i - 1][2])
  eq(d, 1, "steps are one cell, 4-connected (" .. i .. ")")
end

eq(#CellPath.pathTo(res, 1, 1), 0, "the start itself is an empty path")
eq(CellPath.pathTo(res, 3, 2), nil, "a wall cell is unreachable")
eq(CellPath.pathTo(res, 50, 50), nil, "a cell off the map is unreachable")

local shallow = CellPath.search(1, 1, { free = free, maxDepth = 3 })
eq(CellPath.pathTo(shallow, 5, 1), nil, "maxDepth limits the search")
check(CellPath.pathTo(shallow, 2, 3) ~= nil, "...but near cells are still found")

local limited = CellPath.search(1, 1, { free = free, maxDepth = 20, within = function(x, y) return x <= 2 end })
eq(CellPath.pathTo(limited, 5, 1), nil, "`within` keeps the search inside its limit")

eq(CellPath.facingOf(1, 0), "right", "facingOf right")
eq(CellPath.facingOf(-1, 0), "left", "facingOf left")
eq(CellPath.facingOf(0, 1), "down", "facingOf down")
eq(CellPath.facingOf(0, -1), "up", "facingOf up")
eq(CellPath.facingOf(1, 1), nil, "a diagonal is not a facing")

-- a goal: stops when it gets there, with the very path a full search finds
do
  local asked = 0
  local counting = function(x, y) asked = asked + 1 return free(x, y) end
  local full = CellPath.search(1, 1, { free = counting, maxDepth = 20 })
  local fullAsked = asked
  asked = 0
  local toGoal = CellPath.search(1, 1, { free = counting, maxDepth = 20, goalX = 2, goalY = 1 })
  check(toGoal.found, "the goal is found")
  check(asked < fullAsked, "...asking about fewer cells (" .. asked .. " < " .. fullAsked .. ")")
  for _, g in ipairs({ { 2, 1 }, { 5, 1 }, { 2, 3 } }) do
    local a = CellPath.pathTo(full, g[1], g[2])
    local b = CellPath.pathTo(CellPath.search(1, 1, { free = free, maxDepth = 20, goalX = g[1], goalY = g[2] }), g[1], g[2])
    local same = a ~= nil and b ~= nil and #a == #b
    for i = 1, (same and #a or 0) do same = same and a[i][1] == b[i][1] and a[i][2] == b[i][2] end
    check(same, ("the path to %d,%d is the same as without a goal"):format(g[1], g[2]))
  end
  local none = CellPath.search(1, 1, { free = free, maxDepth = 20, goalX = 3, goalY = 2 })
  check(not none.found and CellPath.pathTo(none, 3, 2) == nil, "an unreachable goal: not found, no path")
  check(CellPath.search(4, 4, { free = free, goalX = 4, goalY = 4 }).found, "the start is the goal: found at once")
  -- keys: negative and big coordinates round-trip
  for _, c in ipairs({ { 0, 0 }, { -5, 7 }, { 300, -2 }, { 1000, 1000 } }) do
    local x, y = CellPath.unkey(CellPath.key(c[1], c[2]))
    check(x == c[1] and y == c[2], ("key %d,%d round-trips"):format(c[1], c[2]))
  end
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("cell_path_unit_test: all passed")
