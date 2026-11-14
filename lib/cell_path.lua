-- Breadth-first walking paths over the map's cells, for the companions that
-- walk a little way (lib/forager.lua, lib/overworld_battle.lua) and for wild
-- Pokemon chasing (lib/wild_reactions.lua).
--
-- Pure: which cells are open is a callback. Cells are 4-connected, as the real
-- movement is. Cells are keyed by number (CellPath.key), not by a built string,
-- and a search given a goal stops as soon as it reaches it -- a chase used to flood
-- every cell out to its depth (up to ~1200 for the walk home) on each step.
local CellPath = {}

local STEPS = { { 1, 0, "right" }, { -1, 0, "left" }, { 0, 1, "down" }, { 0, -1, "up" } }
CellPath.STEPS = STEPS

local OFF = 32768
local function key(x, y) return (y + OFF) * 65536 + (x + OFF) end
CellPath.key = key

local floor = math.floor
local function unkey(k)
  local yy = floor(k / 65536)
  return k - yy * 65536 - OFF, yy - OFF
end
CellPath.unkey = unkey

--- Searches outward from (sx, sy). `opts`:
---   free(x, y) -> bool        a cell it may stand on (required)
---   within(x, y) -> bool      optional extra limit (e.g. near the player)
---   maxDepth                  furthest it goes, in steps (default 12)
---   goalX, goalY              optional: stop as soon as this cell is reached (the
---                             path to it is the same one a full search finds)
--- Returns { parent, depth, order, sx, sy, found } where `order` lists the cells found
--- (the start first) in the order reached, as { x, y }; `found` is whether the goal
--- was reached.
function CellPath.search(sx, sy, opts)
  local free, within = opts.free, opts.within
  local maxDepth = opts.maxDepth or 12
  local gx, gy = opts.goalX, opts.goalY
  local k0 = key(sx, sy)
  local parent, depth = { [k0] = false }, { [k0] = 0 }
  local order = { { sx, sy } }
  local res = { parent = parent, depth = depth, order = order, sx = sx, sy = sy, found = false }
  if gx == sx and gy == sy then
    res.found = true
    return res
  end
  local head, n = 1, 1
  while head <= n do
    local c = order[head]
    local x, y = c[1], c[2]
    head = head + 1
    local ck = key(x, y)
    local d = depth[ck]
    if d < maxDepth then
      for i = 1, 4 do
        local s = STEPS[i]
        local nx, ny = x + s[1], y + s[2]
        local k = key(nx, ny)
        if parent[k] == nil and (not within or within(nx, ny)) and free(nx, ny) then
          parent[k] = ck
          depth[k] = d + 1
          n = n + 1
          order[n] = { nx, ny }
          if nx == gx and ny == gy then
            res.found = true
            return res
          end
        end
      end
    end
  end
  return res
end

--- The cells from the search's start (excluded) to (tx, ty), or nil when it was
--- not reached. An empty list means the start itself.
function CellPath.pathTo(res, tx, ty)
  local parent = res.parent
  local k = key(tx, ty)
  if parent[k] == nil then return nil end
  local start = key(res.sx, res.sy)
  local cells, n = {}, 0
  while k ~= start do
    local x, y = unkey(k)
    n = n + 1
    cells[n] = { x, y }
    k = parent[k]
    if not k then return nil end
  end
  local out = {}
  for i = n, 1, -1 do out[#out + 1] = cells[i] end
  return out
end

--- The direction name for a one-cell step (dx, dy), or nil.
function CellPath.facingOf(dx, dy)
  for _, s in ipairs(STEPS) do
    if s[1] == dx and s[2] == dy then return s[3] end
  end
  return nil
end

return CellPath
