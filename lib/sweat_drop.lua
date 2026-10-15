-- The sweat drop of a follower crouching under a roof's edge (lib/eave_duck.lua,
-- lib/follower_adapter.lua): a little light blue teardrop, dark outline, white glint, by
-- its head. Drawn in code; the timing is pure (tested).
local SweatDrop = {}

local SWEAT = {
  { 0, 0, 2, 0, 0 },
  { 0, 2, 1, 2, 0 },
  { 0, 2, 1, 2, 0 },
  { 2, 1, 1, 1, 2 },
  { 2, 1, 3, 1, 2 },
  { 2, 1, 1, 1, 2 },
  { 0, 2, 2, 2, 0 },
}
local SWEAT_COLOURS = { [1] = { 0.58, 0.84, 1.0 }, [2] = { 0.16, 0.36, 0.72 }, [3] = { 1, 1, 1 } }
SweatDrop.SHAPE = SWEAT
SweatDrop.LIFE = 48

--- The drop `age` ticks in: { dy (px, down), alpha } -- it appears, slides 3 px down its
--- head and fades, again every LIFE ticks. Pure (tested).
function SweatDrop.at(age)
  local t = math.max(0, math.floor(tonumber(age) or 0)) % SweatDrop.LIFE
  local p = t / SweatDrop.LIFE
  local alpha = p < 0.15 and p / 0.15 or (p > 0.65 and math.max(0, (1 - p) / 0.35) or 1)
  return math.floor(p * 3 + 0.5), alpha
end

--- The drops a sweating follower shows, pure: { {dx, dy, alpha}, ... } relative to the
--- spot by its head, for `age` ticks in and an `intensity` 0..1 (how hard it is squashed):
--- one drop when light, up to `max` -- the second on the other side of its head, the third
--- a little above the first -- staggered, cycling faster the harder it is squashed.
function SweatDrop.drops(age, intensity, max, span)
  intensity = math.max(0, math.min(1, tonumber(intensity) or 0))
  max = max or 3
  local n = math.max(1, math.min(max, 1 + math.floor(intensity * max)))
  local speed = 1 + intensity -- up to twice as fast
  local t = (tonumber(age) or 0) * speed
  local spots = { { 0, 0 }, { span or -12, 1 }, { 3, -5 } }
  local out = {}
  for k = 1, n do
    local dy, alpha = SweatDrop.at(t + (k - 1) * SweatDrop.LIFE / n)
    local s = spots[k]
    out[#out + 1] = { s[1], s[2] + dy, alpha }
  end
  return out
end

-- the drop baked once into a tiny image: one draw per drop instead of a rectangle per
-- pixel (false: no image support, drawn pixel by pixel)
local sweatImage
local function sweatImg()
  if sweatImage == nil then
    sweatImage = false
    local ok, img = pcall(function()
      local data = love.image.newImageData(#SWEAT[1], #SWEAT)
      for row, line in ipairs(SWEAT) do
        for col, v in ipairs(line) do
          local c = SWEAT_COLOURS[v]
          if c then data:setPixel(col - 1, row - 1, c[1], c[2], c[3], 1) end
        end
      end
      local im = love.graphics.newImage(data)
      im:setFilter("nearest", "nearest")
      return im
    end)
    if ok and img then sweatImage = img end
  end
  return sweatImage
end

--- The sweat as a field actor: `drops` (SweatDrop.drops) about world (x, y) (the first
--- drop's top-left), drawn after the map's upper layer (the roof it is crouching under),
--- `alphaMul` 0..1.
function SweatDrop.actor(drops, x, y, sortY, id, alphaMul)
  return {
    kind = "ow_sweat", elevation = 3, oamPriority = 1, sortY = sortY, x = x, y = y,
    i = 99500 + (tonumber(id) or 0),
    draw = function(_, camX, camY)
      if not (love and love.graphics and love.graphics.rectangle) then return end
      local g = love.graphics
      local r, gg, b, a = g.getColor()
      local img = love.image and love.image.newImageData and g.newImage and sweatImg()
      for _, d in ipairs(drops) do
        local alpha = d[3] * (alphaMul or 1)
        if alpha > 0 and img then
          g.setColor(1, 1, 1, alpha)
          g.draw(img, math.floor(x + d[1] - camX), math.floor(y + d[2] - camY))
        elseif alpha > 0 then
          local x0, y0 = math.floor(x + d[1] - camX), math.floor(y + d[2] - camY)
          for row, line in ipairs(SWEAT) do
            for col, v in ipairs(line) do
              local c = SWEAT_COLOURS[v]
              if c then
                g.setColor(c[1], c[2], c[3], alpha)
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

return SweatDrop
