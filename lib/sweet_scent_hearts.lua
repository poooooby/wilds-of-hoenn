-- The hearts over a wild Pokemon that Sweet Scent called over (SpawnManager:sweetScent).
--
-- Three small hearts, one after another, rise from just above the Pokemon's head with a
-- little side to side sway, fading in and out, for as long as it stays lured; the whole
-- effect fades away over its last second. Drawn in code (a 7 x 6 pixel heart, the
-- engine has no heart sprite on the field in every game), the same way as
-- lib/forage_sparkle.lua: a plain field actor, not an image sheet, so gen3-hd-sprites
-- never spends a layer on it. Without love.graphics (the standalone tests) it draws
-- nothing.
local SweetScentHearts = {}

SweetScentHearts.COUNT = 3     -- hearts in the air at once
SweetScentHearts.RISE_TICKS = 72 -- one heart's life (1.2 s at 60 ticks/s)
SweetScentHearts.RISE_PX = 12  -- how far it climbs
SweetScentHearts.SWAY_PX = 2   -- side to side
SweetScentHearts.FADE_OUT = 60 -- the effect's last ticks of the lure: fading away

-- 7 x 6: 1 = pink body, 2 = dark outline, 3 = white shine
local SHAPE = {
  { 0, 2, 2, 0, 2, 2, 0 },
  { 2, 3, 1, 2, 1, 1, 2 },
  { 2, 1, 1, 1, 1, 1, 2 },
  { 0, 2, 1, 1, 1, 2, 0 },
  { 0, 0, 2, 1, 2, 0, 0 },
  { 0, 0, 0, 2, 0, 0, 0 },
}
SweetScentHearts.SHAPE = SHAPE
local COLOURS = {
  [1] = { 1.0, 0.45, 0.62 },
  [2] = { 0.45, 0.10, 0.22 },
  [3] = { 1.0, 0.92, 0.95 },
}

--- Heart `i` (1..COUNT) `age` ticks into the lure, with `left` ticks of it to go:
--- { dx, dy, alpha } (dy negative = up, from the start point), or nil before it first
--- appears. Pure (tested).
function SweetScentHearts.state(age, i, left)
  age = math.max(0, tonumber(age) or 0)
  local n, life = SweetScentHearts.COUNT, SweetScentHearts.RISE_TICKS
  local t = age - (i - 1) * (life / n) -- staggered starts
  if t < 0 then return nil end
  local p = (t % life) / life -- 0 -> 1 over one rise
  local alpha = math.min(1, p / 0.2) * math.min(1, (1 - p) / 0.3)
  if left ~= nil then alpha = alpha * math.max(0, math.min(1, left / SweetScentHearts.FADE_OUT)) end
  local side = (i % 2 == 0) and -1 or 1
  return {
    dx = side * (2 + (i - 1)) + SweetScentHearts.SWAY_PX * math.sin(p * math.pi * 2),
    dy = -SweetScentHearts.RISE_PX * p,
    alpha = alpha,
  }
end

--- The hearts as one field actor over a Pokemon standing on the tile whose top-left is
--- (wx, wy), its head `lift` px above the tile's ground line.
function SweetScentHearts.actor(wx, wy, lift, age, left, elevation, id)
  local cx, top = wx + 8, wy + 16 - (lift or 20)
  return {
    kind = "ow_sweet_scent_hearts",
    elevation = elevation or 3,
    sortY = wy + 17, -- in front of the Pokemon it floats over
    x = cx, y = top,
    i = 91200 + (tonumber(id) or 0),
    draw = function(_, camX, camY)
      if not (love and love.graphics and love.graphics.rectangle) then return end
      local g = love.graphics
      local r, gg, b, a = g.getColor()
      for i = 1, SweetScentHearts.COUNT do
        local s = SweetScentHearts.state(age, i, left)
        if s and s.alpha > 0.01 then
          local x0 = math.floor(cx + s.dx - 3.5 - camX)
          local y0 = math.floor(top + s.dy - 6 - camY)
          for row, line in ipairs(SHAPE) do
            for col, v in ipairs(line) do
              local c = COLOURS[v]
              if c then
                g.setColor(c[1], c[2], c[3], s.alpha)
                g.rectangle("fill", x0 + col - 1, y0 + row - 1, 1, 1)
              end
            end
          end
        end
      end
      g.setColor(r, gg, b, a)
    end,
  }
end

return SweetScentHearts
