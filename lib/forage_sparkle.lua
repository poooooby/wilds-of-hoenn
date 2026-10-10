-- The glint on the ground where a Forager has sniffed something out.
--
-- It appears when the Pokemon perks up and stays until it has dug the find up,
-- so the player sees where it is running to. It is the same small gold-white
-- twinkle for every find: what it was is only revealed when the Pokemon digs it
-- up. A field actor like lib/hit_effect.lua's; without love.graphics (the
-- standalone tests) it draws nothing.
local ForageSparkle = {}

ForageSparkle.PERIOD = 40 -- ticks per twinkle

--- The glint `age` ticks after it appeared: { alpha, size, rays } -- a slow
--- twinkle that never ends on its own. Pure (tested).
function ForageSparkle.glint(age)
  age = math.max(0, tonumber(age) or 0)
  local phase = (age % ForageSparkle.PERIOD) / ForageSparkle.PERIOD
  local pulse = 0.5 - 0.5 * math.cos(phase * math.pi * 2) -- 0 -> 1 -> 0
  local fadeIn = math.min(1, age / 10)
  return {
    alpha = fadeIn * (0.45 + 0.55 * pulse),
    size = 1.5 + 2.5 * pulse, -- ray length in px
    rays = 4,
  }
end

--- The glint as a field actor on the tile whose top-left is (wx, wy).
function ForageSparkle.actor(wx, wy, age, elevation, id)
  local cx, cy = wx + 8, wy + 10
  return {
    kind = "ow_forage_sparkle",
    elevation = elevation or 3,
    sortY = wy + 2, -- sits on the ground: drawn under a sprite standing on the tile
    x = cx, y = cy,
    i = 90900 + (tonumber(id) or 0),
    draw = function(_, camX, camY)
      if not (love and love.graphics and love.graphics.line) then return end
      local g = love.graphics
      local s = ForageSparkle.glint(age)
      local sx, sy = math.floor(cx - camX), math.floor(cy - camY)
      g.setColor(1, 0.92, 0.55, s.alpha)
      local len = math.floor(s.size + 0.5)
      g.line(sx - len, sy, sx + len, sy)
      g.line(sx, sy - len, sx, sy + len)
      g.setColor(1, 1, 1, s.alpha)
      g.rectangle("fill", sx - 0.5, sy - 0.5, 1, 1)
      g.setColor(1, 1, 1, 1)
    end,
  }
end

return ForageSparkle
