-- Which cells of the current map the player can actually get to from where
-- they stand: a breadth-first flood fill, in the spirit of Wilds of Kanto
-- Revival's cave_reachability.lua. Pure -- every engine rule (walls, ledges,
-- water, HM obstacles) lives in the injected `move` function, built from the
-- engine's own collision functions by EnginePatch.reachMover, so this file
-- reimplements no terrain rule and is directly unit-testable with a fake grid.
--
--   local set, count = Reachability.build({
--     startX = 10, startY = 5, startState = { surfing = false, elev = 3 },
--     move = function(x, y, dir, state) -> nx, ny, newState | nil end,
--   })
--   Reachability.has(set, x, y)
--
-- `move` returns the cell the player would end on when stepping `dir` from
-- (x, y) in `state` -- including a ledge hop two cells away -- and the state
-- they would be in there (walking/surfing, elevation), or nil when the step is
-- blocked. States are carried along each path, so one-way moves (a ledge, a
-- dismount) are one-way here too: the result is "reachable FROM the start",
-- not "connected to".
local Reachability = {}

local DIRS = { "up", "down", "left", "right" }
Reachability.DEFAULT_MAX_CELLS = 60000

--- The set key of a cell.
function Reachability.key(x, y)
  return y * 65536 + x
end

--- True when (x, y) is in a set built by build().
function Reachability.has(set, x, y)
  return set ~= nil and set[Reachability.key(x, y)] == true
end

--- Flood fill. opts: startX, startY, startState, move, maxCells (a safety
--- cap, default DEFAULT_MAX_CELLS). Returns the set and the number of cells;
--- nil when there is no usable start or `move` is missing.
function Reachability.build(opts)
  local move = opts and opts.move
  local sx, sy = opts and tonumber(opts.startX), opts and tonumber(opts.startY)
  if type(move) ~= "function" or not sx or not sy then return nil end
  local maxCells = opts.maxCells or Reachability.DEFAULT_MAX_CELLS

  local set = {}
  local queueX, queueY, queueState = { sx }, { sy }, { opts.startState }
  set[Reachability.key(sx, sy)] = true
  local count, head = 1, 1

  while head <= #queueX and count < maxCells do
    local x, y, state = queueX[head], queueY[head], queueState[head]
    head = head + 1
    for _, dir in ipairs(DIRS) do
      local ok, nx, ny, nstate = pcall(move, x, y, dir, state)
      if ok and nx ~= nil and ny ~= nil then
        local key = Reachability.key(nx, ny)
        if not set[key] then
          set[key] = true
          count = count + 1
          queueX[#queueX + 1], queueY[#queueY + 1], queueState[#queueState + 1] = nx, ny, nstate
        end
      end
    end
  end
  return set, count
end

return Reachability
