-- Breadth-first walking paths over the map's cells, for the companions that
-- walk a little way (lib/forager.lua, lib/overworld_battle.lua).
--
-- Pure: which cells are open is a callback. Cells are 4-connected, as the real
-- movement is.
local CellPath = {}

local STEPS = { { 1, 0, "right" }, { -1, 0, "left" }, { 0, 1, "down" }, { 0, -1, "up" } }
CellPath.STEPS = STEPS

local function key(x, y) return x .. "," .. y end
CellPath.key = key

--- Searches outward from (sx, sy). `opts`:
---   free(x, y) -> bool        a cell it may stand on (required)
---   within(x, y) -> bool      optional extra limit (e.g. near the player)
---   maxDepth                  furthest it goes, in steps (default 12)
--- Returns { parent, depth, order, sx, sy } where `order` lists the cells found
--- (the start first) in the order reached.
function CellPath.search(sx, sy, opts)
  local free, within = opts.free, opts.within
  local maxDepth = opts.maxDepth or 12
  local res = {
    parent = { [key(sx, sy)] = false },
    depth = { [key(sx, sy)] = 0 },
    order = { { sx, sy } },
    sx = sx, sy = sy,
  }
  local head = 1
  while head <= #res.order do
    local x, y = res.order[head][1], res.order[head][2]
    head = head + 1
    local d = res.depth[key(x, y)]
    if d < maxDepth then
      for _, s in ipairs(STEPS) do
        local nx, ny = x + s[1], y + s[2]
        local k = key(nx, ny)
        if res.parent[k] == nil and (not within or within(nx, ny)) and free(nx, ny) then
          res.parent[k] = { x, y }
          res.depth[k] = d + 1
          res.order[#res.order + 1] = { nx, ny }
        end
      end
    end
  end
  return res
end

--- The cells from the search's start (excluded) to (tx, ty), or nil when it was
--- not reached. An empty list means the start itself.
function CellPath.pathTo(res, tx, ty)
  if res.parent[key(tx, ty)] == nil then return nil end
  local cells, x, y = {}, tx, ty
  while not (x == res.sx and y == res.sy) do
    cells[#cells + 1] = { x, y }
    local p = res.parent[key(x, y)]
    if not p then return nil end
    x, y = p[1], p[2]
  end
  local out = {}
  for i = #cells, 1, -1 do out[#out + 1] = cells[i] end
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
