-- Where a flying Pokemon can perch on the current map (lib/sky_flyers.lua): the tops of
-- trees and roofs, and signposts. Built once per map from the engine's own map data
-- (lib/engine_patch.lua), nothing reimplemented:
--   canopy -- a cell nothing walks onto whose metatile draws over actors (the map's upper
--             layer: a tree's crown, a roof). Map tiles only: an object's cell (a Cut tree,
--             an NPC, a boulder) is never a perch.
--   sign   -- a signpost (the map's "sign" background events).
-- Cells next to a warp (a door, a cave mouth) are left out, so nothing sits in a doorway.
local V = ...
local Config = V.require("config")
local EnginePatch = V.require("engine_patch")

local PerchSpots = {}
PerchSpots.__index = PerchSpots

local function nearWarp(x, y)
  if not EnginePatch.isWarpCell then return false end
  for dy = -1, 1 do
    for dx = -1, 1 do
      if EnginePatch.isWarpCell(x + dx, y + dy) then return true end
    end
  end
  return false
end

--- Scans the current map. `opts.maxCells` caps the canopy scan (a huge map keeps a
--- spread-out sample, every n-th cell).
function PerchSpots.build(opts)
  opts = opts or {}
  local self = setmetatable({ list = {}, byKey = {} }, PerchSpots)
  local w, h = EnginePatch.mapBounds()
  local lift = Config.FLYERS.perchLift
  local function add(x, y, kind)
    local key = y * 4096 + x
    if self.byKey[key] then return end
    local spot = { x = x, y = y, kind = kind, lift = lift[kind] or 0 }
    self.byKey[key] = spot
    self.list[#self.list + 1] = spot
  end
  for _, s in ipairs(EnginePatch.signCells and EnginePatch.signCells() or {}) do
    if not nearWarp(s.x, s.y) then add(s.x, s.y, "sign") end
  end
  if EnginePatch.coversActors and w > 0 and h > 0 then
    local stride = 1
    local maxCells = opts.maxCells or 20000
    if w * h > maxCells then stride = math.ceil(w * h / maxCells) end
    local k = 0
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        k = k + 1
        if k % stride == 0 and EnginePatch.isWall(x, y) and not EnginePatch.isWater(x, y)
          and EnginePatch.coversActors(x, y) == true and not EnginePatch.objectOn(x, y)
          and not nearWarp(x, y) then
          add(x, y, "canopy")
        end
      end
    end
  end
  return self
end

--- How many spots there are.
function PerchSpots:count()
  return #self.list
end

--- The spot on (x, y), or nil.
function PerchSpots:at(x, y)
  return self.byKey[y * 4096 + x]
end

--- A random free spot passing `accept(spot)` (true = usable), `tries` attempts; nil when
--- none was found. `taken[spot]` marks spots in use.
function PerchSpots:pick(accept, taken, tries, rng)
  rng = rng or math.random
  local n = #self.list
  if n == 0 then return nil end
  for _ = 1, tries or 24 do
    local s = self.list[rng(1, n)]
    if not (taken and taken[s]) and (not accept or accept(s)) then return s end
  end
  return nil
end

--- Every free spot passing `accept`, for a search near one cell.
function PerchSpots:near(x, y, range, taken)
  local out = {}
  for _, s in ipairs(self.list) do
    if not (taken and taken[s]) and math.max(math.abs(s.x - x), math.abs(s.y - y)) <= range then
      out[#out + 1] = s
    end
  end
  return out
end

return PerchSpots
