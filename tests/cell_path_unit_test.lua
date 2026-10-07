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

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("cell_path_unit_test: all passed")
