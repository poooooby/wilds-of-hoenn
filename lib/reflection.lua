-- Water reflections for our wild Pokemon and the follower, the way the engine draws
-- the player's and every NPC's (field_effects_rse.lua:683 drawReflection,
-- field_effects.lua:194 for FRLG): the sprite mirrored below its feet, shown only on
-- reflective tiles (ponds, puddles, ice ...), with the RSE water's sideways wobble, and
-- the map's upper layer drawn back over it so it stays under bridges and shore tiles.
-- The engine never reflects them because they are not Objects; the `drawBehind` hook
-- (lib/engine_patch.lua) calls Reflection.drawAll right before the engine's own pass.
--
-- A renderer describes the frame it would draw with `reflectionGeometry(x, y, facing,
-- walkPhase)` (lib/actor_renderer.lua, lib/pmd_renderer.lua), in world pixels:
--   image, qx, qy, qw  the frame in its sheet
--   rows               source rows from the frame's top down to the mirror line
--   left               world x of the frame's left edge as drawn
--   mirror             world y of the mirror line (its feet, or a swimmer's waterline)
--   sx, sy             drawn scale (sx < 0 = drawn flipped)
--   alpha              its fade
-- Reflections are drawn at the size the sprite is shown at, in slices (one per
-- reflective tile it covers); gen3-hd-sprites draws those at window resolution when it
-- supports per-quad scales, else they are drawn on the game's pixel grid.
local V = ...
local Config = V.require("config")
local EnginePatch = V.require("engine_patch")
local HdField = V.require("hd_field")

local Reflection = {}

local CELL = 16

--- The reflection's box in world pixels: left, top, width, height, and the x scale it
--- is drawn at (the wobble widens or narrows it about its centre). Pure; for testing.
function Reflection.box(geo, wobble)
  local w = math.abs(geo.sx) * geo.qw
  local sx = math.abs(geo.sx)
  if wobble and wobble > 0 then sx = sx * 256 / wobble end
  local width = geo.qw * sx
  local left = geo.left + w / 2 - width / 2
  local top = geo.mirror - (Config.REFLECTION_OVERLAP or 2)
  return left, top, width, geo.rows * geo.sy, sx
end

--- The part of the sheet that lands in world rect [ix0, ix1) x [iy0, iy1) of a
--- reflection box: source x, y, w, h. The mirror flips it vertically (its first row
--- below the mirror is the frame's last row above it); `flipped` mirrors it sideways
--- too, like the sprite. Pure; for testing.
function Reflection.source(geo, left, top, sx, ix0, ix1, iy0, iy1, flipped)
  local srcW = (ix1 - ix0) / sx
  local srcX = (ix0 - left) / sx
  if flipped then srcX = geo.qw - srcX - srcW end
  local srcH = (iy1 - iy0) / geo.sy
  local srcY = geo.rows - (iy1 - top) / geo.sy
  return geo.qx + srcX, geo.qy + srcY, srcW, srcH
end

-- One quad per slice drawn this frame: gen3-hd-sprites keeps the quad of each draw it
-- catches and reads its viewport again when it composites the frame, so a slice can
-- never reuse a quad another slice of the same frame used. Reset by drawAll.
local pool, used = {}, 0
local function nextQuad(iw, ih)
  if not (love and love.graphics and love.graphics.newQuad) then return nil end
  used = used + 1
  local q = pool[used]
  if not q then
    q = love.graphics.newQuad(0, 0, 1, 1, iw, ih)
    pool[used] = q
  end
  return q
end

-- The engine recolours a reflection with a paler, bluer palette; our art has none, so
-- this shader blends every pixel toward Config.REFLECTION_TINT by REFLECTION_MIX (a
-- multiply could only darken). Without shaders: a plain multiply by the tint.
local shader
local function tintShader()
  if shader == nil then
    shader = false
    if love and love.graphics and love.graphics.newShader then
      local ok, sh = pcall(love.graphics.newShader, [[
        extern vec3 tint;
        extern float amount;
        vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
          vec4 p = Texel(tex, uv);
          return vec4(mix(p.rgb, tint, amount), p.a) * color;
        }
      ]])
      if ok and sh then shader = sh end
    end
  end
  return shader or nil
end

--- The reflection kind under a sprite (0 none, 1 ice, 2 water; EnginePatch.reflectionKind,
--- which walks the tiles below it). Remembered on `cell` -- the caller's record, kept
--- per sprite -- until its tiles or its drawn size change: the engine's walk is up to
--- ~40 tile lookups per sprite, every frame, for an answer that changes only as it moves.
function Reflection.kindOf(geo, cell)
  local w, h = math.abs(geo.sx) * geo.qw, geo.rows * geo.sy
  local cx, cy = cell.cx, cell.cy
  local pcx, pcy = cell.pcx or cx, cell.pcy or cy
  if cell.kind ~= nil and cell.kcx == cx and cell.kcy == cy and cell.kpcx == pcx and cell.kpcy == pcy
    and cell.kw == w and cell.kh == h then
    return cell.kind
  end
  local kind = EnginePatch.reflectionKind(cx, cy, pcx, pcy, w, h)
  cell.kind, cell.kcx, cell.kcy, cell.kpcx, cell.kpcy, cell.kw, cell.kh = kind, cx, cy, pcx, pcy, w, h
  return kind
end

-- What the slice pass draws, set by Reflection.draw just before it: the pass is a plain
-- function (no closure built per reflection per frame), run directly or through
-- HdField.untagged.
local cur = { geo = nil, left = 0, top = 0, width = 0, height = 0, sx = 1, iw = 1, ih = 1,
  flipped = false, hd = false, camX = 0, camY = 0, drawn = false }
local tintBuf = { 1, 1, 1 }

local function drawSlices()
  local geo, left, top, width, height, sx = cur.geo, cur.left, cur.top, cur.width, cur.height, cur.sx
  local iw, ih, flipped, hd, camX, camY = cur.iw, cur.ih, cur.flipped, cur.hd, cur.camX, cur.camY
  local tint = Config.REFLECTION_TINT or tintBuf
  local sh = tintShader()
  if sh then
    tintBuf[1], tintBuf[2], tintBuf[3] = tint[1], tint[2], tint[3]
    pcall(sh.send, sh, "tint", tintBuf)
    pcall(sh.send, sh, "amount", Config.REFLECTION_MIX or 0.5)
    love.graphics.setShader(sh)
    love.graphics.setColor(1, 1, 1, geo.alpha or 1)
  else
    love.graphics.setColor(tint[1], tint[2], tint[3], geo.alpha or 1)
  end
  for ty = math.floor(top / CELL), math.floor((top + height - 1) / CELL) do
    for tx = math.floor(left / CELL), math.floor((left + width - 1) / CELL) do
      if EnginePatch.reflectiveAt(tx, ty) then
        local ix0, ix1 = math.max(left, tx * CELL), math.min(left + width, (tx + 1) * CELL)
        local iy0, iy1 = math.max(top, ty * CELL), math.min(top + height, (ty + 1) * CELL)
        local q = (ix1 > ix0 and iy1 > iy0) and nextQuad(iw, ih)
        if q then
          local srcX, srcY, srcW, srcH = Reflection.source(geo, left, top, sx, ix0, ix1, iy0, iy1, flipped)
          q:setViewport(srcX, srcY, srcW, srcH, iw, ih)
          if hd then HdField.quadPivot(geo.image, q, 0, 0, 1) end
          love.graphics.draw(geo.image, q,
            (flipped and ix1 or ix0) - camX, iy1 - camY, 0, flipped and -sx or sx, -geo.sy)
          cur.drawn = true
        end
      end
    end
  end
  if sh then love.graphics.setShader() end
  love.graphics.setColor(1, 1, 1, 1)
end

--- Draw one reflection. `cell` = { cx, cy, pcx, pcy }: the tile it stands on (or is
--- stepping onto) and the one it comes from, which decide whether there is water below
--- (the answer is remembered on it, Reflection.kindOf). Returns its world box (left,
--- top, width, height) when something was drawn (for the cover pass), else nil.
--- With gen3-hd-sprites (one that takes per-quad scales) the slices are drawn through
--- it at window resolution, each at scale 1 -- they are already the size the sprite is
--- shown at, so they land exactly where the plain draw would put them; without it, or
--- with an older one, they are drawn the plain way.
function Reflection.draw(geo, cell, camX, camY)
  if not (geo and geo.image and geo.rows and geo.rows > 0 and geo.qw and geo.qw > 0) then return nil end
  if (geo.alpha or 1) <= 0 then return nil end
  local kind = Reflection.kindOf(geo, cell)
  if kind == 0 then return nil end
  local wobble = (kind == 2) and EnginePatch.reflectionWobble() or nil
  local left, top, width, height, sx = Reflection.box(geo, wobble)
  local iw, ih = geo.image:getDimensions()
  cur.geo, cur.left, cur.top, cur.width, cur.height, cur.sx = geo, left, top, width, height, sx
  cur.iw, cur.ih, cur.flipped, cur.camX, cur.camY = iw, ih, geo.sx < 0, camX, camY
  cur.hd = HdField.slicesSupported(geo.mod, geo.image)
  cur.drawn = false
  if cur.hd then drawSlices() else HdField.untagged(geo.mod, geo.image, drawSlices) end
  cur.geo = nil
  if not cur.drawn then return nil end
  return left, top, width, height
end

-- the cover pass's boxes, 4 numbers each, reused frame to frame
local boxes = {}

--- Draw the first `n` (default all) reflections in `list` ({ geo, cell } records), then
--- the map's upper layer back over them. Returns how many were drawn.
function Reflection.drawAll(list, camX, camY, n)
  used = 0
  local nb = 0
  for i = 1, n or #list do
    local item = list[i]
    local ok, left, top, width, height = pcall(Reflection.draw, item.geo, item.cell, camX, camY)
    if ok and left then
      boxes[nb + 1], boxes[nb + 2], boxes[nb + 3], boxes[nb + 4] = left, top, width, height
      nb = nb + 4
    end
  end
  for b = 1, nb, 4 do
    EnginePatch.coverReflections(boxes[b], boxes[b + 1], boxes[b + 2], boxes[b + 3], camX, camY)
  end
  return nb / 4
end

return Reflection
