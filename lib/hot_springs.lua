-- The hot spring water over the follower's lower half (Lavaridge Town's spa).
--
-- The engine draws its `hot_springs_water` field effect (a light blue band over the bottom of
-- a tile) over the player and every registered object whose cell AND the cell it is stepping
-- to are both hot spring tiles (field_effects.lua, pokefirered event_object_movement.c:8196
-- GroundEffect_HotSprings / field_effect_helpers.c:792). The follower is not an Objects
-- entity, so the engine's loop never reaches it: it stood in the spa bone dry. This draws the
-- same band, from the same sheet, over it -- the rule the engine uses, at the sprite's DRAWN
-- feet (the follower is spaced away from its own tile), across the whole art (never narrower
-- than the player's 16 px), cut to the hot spring tiles, so no water shows on the bank.
local V = ...
local EnginePatch = V.require("engine_patch")

local HotSprings = {}

local CELL = 16

-- A map's tiles never change, so each tile's answer is kept until the next map
-- (HotSprings.reset, lib/spawn_manager.lua onMapEntered). key -> true / false.
local tiles = {}

local function isSpring(cx, cy)
  local k = cy * 65536 + cx
  local hit = tiles[k]
  if hit == nil then
    hit = EnginePatch.isHotSprings and EnginePatch.isHotSprings(cx, cy) == true or false
    tiles[k] = hit
  end
  return hit
end
HotSprings.isSpring = isSpring

-- pooled actors, one per (owner, copy), refilled each frame; one shared draw
local pool = {}

local function drawWater(a, camX, camY)
  love.graphics.setColor(1, 1, 1, a.alpha or 1)
  love.graphics.draw(a.sheet.image, a.quad, a.x - camX, a.y - camY)
  love.graphics.setColor(1, 1, 1, 1)
end

local function water(key)
  local a = pool[key]
  if not a then
    a = { kind = "field_effect_wild_hot_springs", draw = drawWater }
    pool[key] = a
  end
  return a
end

--- A new map: forget the tiles.
function HotSprings.reset()
  tiles = {}
end

--- Is an entity on (cellX, cellY), stepping to (toX, toY) (its own cell when standing), in
--- the spa by the engine's rule (both cells hot springs)?
function HotSprings.inSprings(cellX, cellY, toX, toY)
  if type(cellX) ~= "number" or type(cellY) ~= "number" then return false end
  if not isSpring(cellX, cellY) then return false end
  return isSpring(toX or cellX, toY or cellY)
end

--- The band's pieces for art `width` px wide, feet centred on `fx`, in tile row `row`: a list
--- of { x, srcX, w } (world left edge, the column of the 16 px tile it starts from, its width),
--- written into `out`. The band spans the whole art plus a margin (over the spring's own water
--- it is the water's colour, so only where it crosses the art does it show) -- never narrower
--- than the player's 16 px -- cut to the hot spring TILES under it: each piece is one tile's
--- share, drawn from that tile's own columns of the sheet, as the spring water is laid out.
--- `spring(cx, cy)` says which tiles are. Pure; for testing.
function HotSprings.pieces(fx, width, row, spring, out)
  out = out or {}
  local W = math.floor((tonumber(width) or CELL) * HotSprings.WIDTH + 0.5) + 2 * HotSprings.MARGIN
  W = math.max(CELL, math.min(HotSprings.MAX_WIDTH, W))
  local x0 = math.floor(fx - W / 2 + 0.5)
  local x1 = x0 + W
  local n = 0
  for col = math.floor(x0 / CELL), math.floor((x1 - 1) / CELL) do
    if spring(col, row) then
      local a, b = math.max(x0, col * CELL), math.min(x1, col * CELL + CELL)
      if b > a then
        n = n + 1
        local p = out[n]
        if not p then p = {} out[n] = p end
        p[1], p[2], p[3] = a, a - col * CELL, b - a
      end
    end
  end
  for k = #out, n + 1, -1 do out[k] = nil end
  return out, n
end

--- The band spans the art's width x WIDTH + MARGIN px each side, at most MAX_WIDTH.
HotSprings.WIDTH = 1
HotSprings.MARGIN = 2
HotSprings.MAX_WIDTH = 192

-- a quad for `w` columns of the tile from `srcX`, kept per (image, srcX, w)
local quads = setmetatable({}, { __mode = "k" })
local function quadFor(sheet, q, srcX, w)
  if srcX == 0 and w == CELL then return q end
  local byImg = quads[sheet.image]
  if not byImg then byImg = {} quads[sheet.image] = byImg end
  local k = srcX * 64 + w -- (srcX, w <= 16)
  local hit = byImg[k]
  if hit == nil then
    hit = false
    pcall(function()
      local qx, qy = q:getViewport()
      hit = love.graphics.newQuad(qx + srcX, qy, w, CELL, sheet.image:getDimensions())
    end)
    byImg[k] = hit
  end
  return hit or nil
end

local scratch = {}

--- Appends the water band over a sprite whose feet are at (fx, fy) (world px; fx their
--- centre), `width` its art's width, standing on (cellX, cellY) and stepping to (toX, toY).
--- `sortY` puts it right after the sprite (the sprite's own sortY + 0.5), `alpha` fades it
--- with the sprite. Nothing outside the spa, or before the sheet can load; each piece only
--- over a hot spring tile (no water on the bank).
function HotSprings.append(actors, fx, fy, width, cellX, cellY, toX, toY, sortY, elevation, idBase, alpha)
  if type(fx) ~= "number" or type(fy) ~= "number" then return end
  if not HotSprings.inSprings(cellX, cellY, toX, toY) then return end
  if not EnginePatch.hotSpringsSheet then return end
  local sheet, q = EnginePatch.hotSpringsSheet()
  if not q then return end
  local row = math.floor((fy - 1) / CELL)
  local list, n = HotSprings.pieces(fx, width, row, isSpring, scratch)
  local top = math.floor(fy + 0.5) - CELL -- the band's tile, bottom edge on the feet
  local id = tonumber(idBase) or 0
  for k = 1, n do
    local p = list[k]
    local x, srcX, w = p[1], p[2], p[3]
    local pq = quadFor(sheet, q, srcX, w)
    if pq then
      local a = water(id * 16 + k)
      a.elevation, a.sortY = elevation or 3, (sortY or fy) + 0.5
      a.x, a.y, a.i = x, top, 91600 + id * 16 + k
      a.sheet, a.quad, a.alpha = sheet, pq, alpha
      actors[#actors + 1] = a
    end
  end
end

return HotSprings
