-- The small health bar floating over a fighter in an overworld skirmish.
--
-- A field actor (same shape as lib/grass_cover.lua's): sorted in front of the
-- sprites, scrolling with the camera, snapped to whole pixels. The colour
-- follows the usual Gen 3 thresholds (green, yellow under half, red under a
-- fifth).
local HealthBar = {}

local WIDTH = 16

--- Fill ratio -> { r, g, b }.
function HealthBar.colorFor(ratio)
  if ratio <= 0.2 then return 0.9, 0.2, 0.15 end
  if ratio <= 0.5 then return 0.95, 0.8, 0.15 end
  return 0.25, 0.85, 0.35
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
      g.setColor(0.1, 0.1, 0.12, 1)
      g.rectangle("fill", x - 1, y - 1, WIDTH + 2, 4)
      g.setColor(0.45, 0.45, 0.5, 1)
      g.rectangle("fill", x, y, WIDTH, 2)
      local w = HealthBar.fillWidth(ratio, hp > 0)
      if w > 0 then
        g.setColor(HealthBar.colorFor(ratio))
        g.rectangle("fill", x, y, w, 2)
      end
      g.setColor(1, 1, 1, 1)
    end,
  }
end

HealthBar.WIDTH = WIDTH

return HealthBar
