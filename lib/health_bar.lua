-- The small health bar floating over a fighter in an overworld skirmish.
--
-- A field actor (same shape as lib/grass_cover.lua's): sorted in front of the
-- sprites, scrolling with the camera, snapped to whole pixels. Drawn like the
-- battle HP bar: a dark outline round three rows, the middle row bright and
-- the top and bottom rows its shade; the empty part is white over grey. The
-- colour follows the usual Gen 3 thresholds (green, yellow under half, red
-- under a fifth).
local HealthBar = {}

local WIDTH = 16

local function rgb(r, g, b) return { r / 255, g / 255, b / 255 } end
local OUTLINE = rgb(16, 16, 16)
local EMPTY = { light = rgb(243, 243, 243), dark = rgb(154, 146, 154) }
local GREEN = { light = rgb(0, 251, 73), dark = rgb(0, 138, 40) }
local YELLOW = { light = rgb(248, 224, 56), dark = rgb(184, 136, 0) }
local RED = { light = rgb(248, 88, 56), dark = rgb(168, 48, 40) }

--- Fill ratio -> the bar's { light, dark } colours.
function HealthBar.paletteFor(ratio)
  if ratio <= 0.2 then return RED end
  if ratio <= 0.5 then return YELLOW end
  return GREEN
end

--- Fill ratio -> r, g, b of the bright middle row.
function HealthBar.colorFor(ratio)
  local c = HealthBar.paletteFor(ratio).light
  return c[1], c[2], c[3]
end

-- The whole bar is drawn a little see-through, so every pixel is drawn once
-- (overlapping translucent rects would darken where they cross).
local ALPHA = 0.8

-- A three-row band: the shade on the top and bottom rows, the bright row between.
local function band(g, x, y, w, colours)
  g.setColor(colours.dark[1], colours.dark[2], colours.dark[3], ALPHA)
  g.rectangle("fill", x, y, w, 1)
  g.rectangle("fill", x, y + 2, w, 1)
  g.setColor(colours.light[1], colours.light[2], colours.light[3], ALPHA)
  g.rectangle("fill", x, y + 1, w, 1)
end

--- Pixels of fill for `ratio` (a living fighter always shows at least 1).
function HealthBar.fillWidth(ratio, alive)
  ratio = math.max(0, math.min(1, tonumber(ratio) or 0))
  local w = math.floor(WIDTH * ratio + 0.5)
  if alive and w < 1 then w = 1 end
  return w
end

--- The bar as a field actor over the tile whose top-left is (wx, wy) in world
--- px; `lift` px above the tile's ground line (the sprite's height).
function HealthBar.actor(wx, wy, hp, maxHp, lift, elevation, id)
  maxHp = tonumber(maxHp) or 1
  if maxHp < 1 then maxHp = 1 end
  hp = tonumber(hp) or 0
  local ratio = math.max(0, math.min(1, hp / maxHp))
  local gx, gy = wx + 8, wy + 12 - (lift or 16)
  return {
    kind = "ow_health_bar",
    elevation = elevation or 3,
    sortY = wy + 80,
    x = gx, y = gy,
    i = 90700 + (tonumber(id) or 0),
    draw = function(_, camX, camY)
      if not (love and love.graphics and love.graphics.rectangle) then return end
      local x = math.floor(gx - camX - WIDTH / 2)
      local y = math.floor(gy - camY)
      local g = love.graphics
      g.setColor(OUTLINE[1], OUTLINE[2], OUTLINE[3], ALPHA)
      g.rectangle("fill", x - 1, y - 1, WIDTH + 2, 1)
      g.rectangle("fill", x - 1, y + 3, WIDTH + 2, 1)
      g.rectangle("fill", x - 1, y, 1, 3)
      g.rectangle("fill", x + WIDTH, y, 1, 3)
      local w = HealthBar.fillWidth(ratio, hp > 0)
      if w < WIDTH then band(g, x + w, y, WIDTH - w, EMPTY) end
      if w > 0 then band(g, x, y, w, HealthBar.paletteFor(ratio)) end
      g.setColor(1, 1, 1, 1)
    end,
  }
end

HealthBar.WIDTH = WIDTH
HealthBar.ALPHA = ALPHA

return HealthBar
