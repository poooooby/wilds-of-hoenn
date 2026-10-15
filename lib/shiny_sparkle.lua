-- The twinkle on a shiny Pokemon in the overworld (a wild spawn, lib/spawn_manager.lua, or
-- the partner, lib/follower_adapter.lua).
--
-- Every PERIOD ticks a short burst: COUNT little four-point stars pop on its body one after
-- another, grow, shrink and fade -- the shiny sparkle of the later games, small and quick.
-- Each Pokemon is offset by its id, so a few shinies on screen never twinkle in step.
-- Drawn in code (two tiny star shapes, baked once into images; pixel by pixel without
-- image support) as a plain field actor, so gen3-hd-sprites never spends a layer on it.
-- `ShinySparkle.burst` is pure (tested).
local V = ...
local ShinySparkle = {}

ShinySparkle.PERIOD = 180 -- ticks between bursts (3 s)
ShinySparkle.COUNT = 3    -- stars in a burst
ShinySparkle.STAGGER = 6  -- ticks between one star and the next
ShinySparkle.LIFE = 18    -- one star's life

-- 1 = gold, 2 = white core
local SMALL = {
  { 0, 1, 0 },
  { 1, 2, 1 },
  { 0, 1, 0 },
}
local BIG = {
  { 0, 0, 1, 0, 0 },
  { 0, 0, 1, 0, 0 },
  { 1, 1, 2, 1, 1 },
  { 0, 0, 1, 0, 0 },
  { 0, 0, 1, 0, 0 },
}
local COLOURS = { { 1.0, 0.86, 0.35 }, { 1, 1, 1 } }
ShinySparkle.SHAPES = { small = SMALL, big = BIG }

-- where on the body the stars of a burst land: { x as a share of half the width (-1..1),
-- y as a share of the height down from the top (0..1) }, a few sets taken in turn
local SPOTS = {
  { { -0.5, 0.30 }, { 0.45, 0.15 }, { 0.05, 0.60 } },
  { { 0.40, 0.45 }, { -0.35, 0.10 }, { -0.05, 0.70 } },
  { { 0.10, 0.20 }, { -0.55, 0.55 }, { 0.50, 0.65 } },
}

--- The stars to draw `age` ticks into the Pokemon's life (`id` sets its own rhythm):
--- { {shape, sx, sy, alpha}, ... } with sx -1..1 across the body, sy 0..1 down it.
function ShinySparkle.burst(age, id)
  age = math.max(0, math.floor(tonumber(age) or 0))
  local offset = ((tonumber(id) or 0) * 53) % ShinySparkle.PERIOD
  local t = (age + offset) % ShinySparkle.PERIOD
  local n = math.floor((age + offset) / ShinySparkle.PERIOD)
  local spots = SPOTS[(n % #SPOTS) + 1]
  local out = {}
  for i = 1, ShinySparkle.COUNT do
    local u = t - (i - 1) * ShinySparkle.STAGGER
    if u >= 0 and u < ShinySparkle.LIFE then
      local p = u / ShinySparkle.LIFE
      local shape = (p > 0.25 and p < 0.7) and "big" or "small"
      local alpha = math.min(1, p / 0.15) * math.min(1, (1 - p) / 0.3)
      local s = spots[i]
      out[#out + 1] = { shape, s[1], s[2], alpha }
    end
  end
  return out
end

local images = {}
local function imageFor(name)
  local hit = images[name]
  if hit ~= nil then return hit end
  images[name] = false
  local rows = ShinySparkle.SHAPES[name]
  if not (rows and love and love.image and love.image.newImageData and love.graphics and love.graphics.newImage) then
    return false
  end
  local ok, img = pcall(function()
    local data = love.image.newImageData(#rows[1], #rows)
    for y, line in ipairs(rows) do
      for x, v in ipairs(line) do
        local c = COLOURS[v]
        if c then data:setPixel(x - 1, y - 1, c[1], c[2], c[3], 1) end
      end
    end
    local im = love.graphics.newImage(data)
    im:setFilter("nearest", "nearest")
    return im
  end)
  if ok and img then images[name] = img end
  return images[name]
end

--- How wide a renderer's art is drawn (px): HGSS visualWidth, PMD its content size.
function ShinySparkle.bodyWidth(r)
  if not r then return 16 end
  if r.visualWidth then
    local ok, w = pcall(r.visualWidth, r)
    if ok and tonumber(w) and w > 0 then return w end
  end
  if r.isPmd and r.info then
    local okP, PmdRenderer = pcall(V.require, "pmd_renderer")
    if okP and PmdRenderer and PmdRenderer.contentSize then
      local w = PmdRenderer.contentSize(r.info, r.hdScale and r:hdScale() or 1)
      if tonumber(w) and w > 0 then return w end
    end
  end
  return 16
end

--- The twinkle as one field actor over a body centred on world x `cx`, from `top` (world
--- y of its head) `height` px down, `halfWidth` px either side; in front of it (sortY).
--- nil while no star of the burst is showing.
function ShinySparkle.actor(age, id, cx, top, height, halfWidth, sortY, elevation)
  local stars = ShinySparkle.burst(age, id)
  if #stars == 0 then return nil end
  return {
    kind = "ow_shiny_sparkle", elevation = elevation or 3, sortY = sortY, x = cx, y = top,
    i = 99700 + (tonumber(id) or 0) % 1000,
    draw = function(_, camX, camY)
      if not (love and love.graphics and love.graphics.rectangle) then return end
      local g = love.graphics
      local r, gg, b, a = g.getColor()
      for _, s in ipairs(stars) do
        local rows = ShinySparkle.SHAPES[s[1]]
        local w, h = #rows[1], #rows
        local x0 = math.floor(cx + s[2] * halfWidth - w / 2 - camX)
        local y0 = math.floor(top + s[3] * height - h / 2 - camY)
        local img = imageFor(s[1])
        if img then
          g.setColor(1, 1, 1, s[4])
          g.draw(img, x0, y0)
        else
          for y, line in ipairs(rows) do
            for x, v in ipairs(line) do
              local c = COLOURS[v]
              if c then
                g.setColor(c[1], c[2], c[3], s[4])
                g.rectangle("fill", x0 + x - 1, y0 + y - 1, 1, 1)
              end
            end
          end
        end
      end
      g.setColor(r, gg, b, a)
    end,
  }
end

return ShinySparkle
