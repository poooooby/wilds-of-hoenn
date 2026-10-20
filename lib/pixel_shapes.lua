-- Little code-drawn pixel shapes (hearts, flames, droplets ...): rows of colour numbers,
-- each shape baked once into a tiny nearest-filtered image and drawn like a sprite, or
-- pixel by pixel when images are unavailable. Shared by lib/mood_fx.lua (the partner's
-- moods) and lib/finisher_fx.lua (the Battler's knockout effects); neither tags its
-- draws, so gen3-hd-sprites never spends a layer on them.
local PixelShapes = {}

-- name -> { rows = { {n, ...}, ... }, colours = { {r, g, b}, ... } }; 0 = clear
local SHAPES = {}
PixelShapes.SHAPES = SHAPES

local images = {} -- name -> Image (false: no image support)

--- Registers (or replaces) a shape.
function PixelShapes.define(name, rows, colours)
  SHAPES[name] = { rows = rows, colours = colours }
  images[name] = nil
end

--- Registers every entry of a { name = { rows, colours } } table.
function PixelShapes.defineAll(list)
  for name, s in pairs(list) do PixelShapes.define(name, s.rows, s.colours) end
end

function PixelShapes.get(name) return SHAPES[name] end

--- Width, height in pixels (0, 0 for an unknown shape).
function PixelShapes.size(name)
  local s = SHAPES[name]
  if not s then return 0, 0 end
  return #s.rows[1], #s.rows
end

local function imageFor(name)
  local hit = images[name]
  if hit ~= nil then return hit end
  images[name] = false
  local s = SHAPES[name]
  if not (s and love and love.image and love.image.newImageData and love.graphics and love.graphics.newImage) then
    return false
  end
  local ok, img = pcall(function()
    local data = love.image.newImageData(#s.rows[1], #s.rows)
    for row, line in ipairs(s.rows) do
      for col, v in ipairs(line) do
        local c = s.colours[v]
        if c then data:setPixel(col - 1, row - 1, c[1], c[2], c[3], 1) end
      end
    end
    local im = love.graphics.newImage(data)
    im:setFilter("nearest", "nearest")
    return im
  end)
  if ok and img then images[name] = img end
  return images[name]
end

--- Draws shape `name` with its top-left at (x0, y0). `tint` {r, g, b} multiplies its
--- colours (nil = as defined); `scale` enlarges it about its top-left (pixel art, nearest).
function PixelShapes.draw(g, name, x0, y0, alpha, tint, scale)
  local s = SHAPES[name]
  if not s or (alpha or 1) <= 0 then return end
  local tr, tg, tb = 1, 1, 1
  if tint then tr, tg, tb = tint[1], tint[2], tint[3] end
  scale = scale or 1
  local img = imageFor(name)
  if img then
    g.setColor(tr, tg, tb, alpha or 1)
    g.draw(img, x0, y0, 0, scale, scale)
    return
  end
  for row, line in ipairs(s.rows) do
    for col, v in ipairs(line) do
      local c = s.colours[v]
      if c then
        g.setColor(c[1] * tr, c[2] * tg, c[3] * tb, alpha or 1)
        g.rectangle("fill", x0 + (col - 1) * scale, y0 + (row - 1) * scale, scale, scale)
      end
    end
  end
end

return PixelShapes
