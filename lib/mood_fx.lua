-- Little drawn effects over the partner while you Pet / Play / Talk with it
-- (lib/follower_interaction.lua), matching the face its portrait shows: hearts when it
-- loves you, music notes when it's happy, a rain cloud when it's sad, an anger mark when
-- it's cross, and for a hurting one its trouble (poison bubbles, flames, sparks,
-- snowflakes, Zs, sweat).
--
-- Drawn in code (small pixel shapes, each baked once into a tiny image; pixel by pixel
-- without image support), as a plain field actor like lib/sweat_drop.lua, so
-- gen3-hd-sprites never spends a layer on it. `MoodFx.kindFor` and `MoodFx.particles`
-- are pure (tested).
local MoodFx = {}

-- ------------------------------------------------------------------ shapes
-- Rows of colour numbers, 0 = clear; each shape has its own palette.
local SHAPES = {
  heart = {
    rows = {
      { 0, 2, 2, 0, 2, 2, 0 },
      { 2, 3, 1, 2, 1, 1, 2 },
      { 2, 1, 1, 1, 1, 1, 2 },
      { 0, 2, 1, 1, 1, 2, 0 },
      { 0, 0, 2, 1, 2, 0, 0 },
      { 0, 0, 0, 2, 0, 0, 0 },
    },
    colours = { { 1.0, 0.45, 0.62 }, { 0.45, 0.10, 0.22 }, { 1.0, 0.92, 0.95 } },
  },
  note = {
    rows = {
      { 0, 0, 1, 1, 1 },
      { 0, 0, 1, 0, 1 },
      { 0, 0, 1, 0, 0 },
      { 0, 0, 1, 0, 0 },
      { 1, 1, 1, 0, 0 },
      { 1, 2, 1, 0, 0 },
      { 1, 1, 0, 0, 0 },
    },
    colours = { { 0.16, 0.22, 0.52 }, { 0.55, 0.70, 1.0 } },
  },
  sparkle = {
    rows = {
      { 0, 0, 1, 0, 0 },
      { 0, 0, 2, 0, 0 },
      { 1, 2, 2, 2, 1 },
      { 0, 0, 2, 0, 0 },
      { 0, 0, 1, 0, 0 },
    },
    colours = { { 1.0, 0.82, 0.25 }, { 1.0, 1.0, 0.9 } },
  },
  cloud = {
    rows = {
      { 0, 0, 2, 2, 2, 0, 0, 0, 0 },
      { 0, 2, 1, 1, 1, 2, 2, 2, 0 },
      { 2, 1, 1, 1, 1, 1, 1, 1, 2 },
      { 2, 1, 1, 1, 1, 1, 1, 1, 2 },
      { 0, 2, 2, 2, 2, 2, 2, 2, 0 },
    },
    colours = { { 0.66, 0.70, 0.78 }, { 0.32, 0.35, 0.44 } },
  },
  raindrop = {
    rows = { { 1 }, { 1 } },
    colours = { { 0.40, 0.62, 0.95 } },
  },
  tear = {
    rows = {
      { 0, 2, 0 },
      { 2, 1, 2 },
      { 2, 1, 2 },
      { 0, 2, 0 },
    },
    colours = { { 0.62, 0.86, 1.0 }, { 0.20, 0.42, 0.78 } },
  },
  sweat = {
    rows = {
      { 0, 0, 2, 0, 0 },
      { 0, 2, 1, 2, 0 },
      { 0, 2, 1, 2, 0 },
      { 2, 1, 1, 1, 2 },
      { 2, 1, 3, 1, 2 },
      { 2, 1, 1, 1, 2 },
      { 0, 2, 2, 2, 0 },
    },
    colours = { { 0.58, 0.84, 1.0 }, { 0.16, 0.36, 0.72 }, { 1, 1, 1 } },
  },
  anger = {
    rows = {
      { 0, 1, 1, 0, 1, 1, 0 },
      { 1, 1, 0, 0, 0, 1, 1 },
      { 1, 0, 0, 0, 0, 0, 1 },
      { 0, 0, 0, 0, 0, 0, 0 },
      { 1, 0, 0, 0, 0, 0, 1 },
      { 1, 1, 0, 0, 0, 1, 1 },
      { 0, 1, 1, 0, 1, 1, 0 },
    },
    colours = { { 0.90, 0.16, 0.16 } },
  },
  exclaim = {
    rows = {
      { 2, 2, 2, 2 },
      { 2, 1, 1, 2 },
      { 2, 1, 1, 2 },
      { 2, 1, 1, 2 },
      { 0, 2, 2, 0 },
      { 2, 1, 1, 2 },
      { 2, 2, 2, 2 },
    },
    colours = { { 0.92, 0.18, 0.18 }, { 1, 1, 1 } },
  },
  zee = {
    rows = {
      { 1, 1, 1, 1 },
      { 0, 0, 1, 0 },
      { 0, 1, 0, 0 },
      { 1, 1, 1, 1 },
    },
    colours = { { 0.24, 0.30, 0.66 } },
  },
  bubble = {
    rows = {
      { 0, 1, 1, 0 },
      { 1, 2, 0, 1 },
      { 1, 0, 0, 1 },
      { 0, 1, 1, 0 },
    },
    colours = { { 0.62, 0.30, 0.78 }, { 0.95, 0.85, 1.0 } },
  },
  flame = {
    rows = {
      { 0, 0, 1, 0, 0 },
      { 0, 1, 1, 0, 0 },
      { 0, 1, 2, 1, 0 },
      { 1, 2, 3, 2, 1 },
      { 1, 2, 3, 2, 1 },
      { 0, 1, 2, 1, 0 },
    },
    colours = { { 0.92, 0.30, 0.10 }, { 1.0, 0.62, 0.15 }, { 1.0, 0.92, 0.45 } },
  },
  spark = {
    rows = {
      { 0, 0, 1 },
      { 0, 1, 0 },
      { 1, 1, 1 },
      { 0, 1, 0 },
      { 1, 0, 0 },
    },
    colours = { { 1.0, 0.90, 0.20 } },
  },
  snow = {
    rows = {
      { 1, 0, 1, 0, 1 },
      { 0, 1, 1, 1, 0 },
      { 1, 1, 2, 1, 1 },
      { 0, 1, 1, 1, 0 },
      { 1, 0, 1, 0, 1 },
    },
    colours = { { 0.62, 0.86, 1.0 }, { 1, 1, 1 } },
  },
}
MoodFx.SHAPES = SHAPES

-- ------------------------------------------------------------------ which effect
-- by the portrait's face (lib/mon_mood.lua emotions); a pained face goes by its status
local BY_EMOTION = {
  Inspired = "love", Joyous = "hearts", Happy = "notes", Determined = "sparkles",
  Surprised = "exclaim", Sad = "rain", ["Teary-Eyed"] = "tears", Crying = "tears",
  Angry = "anger", Worried = "sweat",
}
local BY_STATUS = { poison = "bubbles", burn = "flame", paralysis = "sparks", freeze = "snow", sleep = "zzz" }
local PAINED = { Pain = true, Shouting = true, Stunned = true, Dizzy = true }

--- The effect for a portrait `emotion` and a status ("poison" | "burn" | "paralysis" |
--- "freeze" | "sleep" | nil), or nil (a calm Normal face shows nothing).
function MoodFx.kindFor(emotion, status)
  if PAINED[emotion] then
    return BY_STATUS[status] or (emotion == "Dizzy" and "zzz") or "sweat"
  end
  return BY_EMOTION[emotion]
end

-- ------------------------------------------------------------------ motion
local LIFE = 60 -- ticks one rising / falling particle lives

local function cycle(age, i, n, life)
  local t = age - (i - 1) * (life / n)
  if t < 0 then return nil end
  return (t % life) / life
end

local function fadeInOut(p, inn, out)
  return math.min(1, p / inn) * math.min(1, (1 - p) / out)
end

-- three of `shape` rising from the head, swaying, alternating sides
local function rising(out, age, shape, spread, rise, sway)
  for i = 1, 3 do
    local p = cycle(age, i, 3, LIFE)
    if p then
      local side = (i % 2 == 0) and -1 or 1
      out[#out + 1] = { shape, side * spread + sway * math.sin(p * math.pi * 2), -rise * p, fadeInOut(p, 0.2, 0.3) }
    end
  end
end

-- `n` of `shape` twinkling on and off at fixed spots
local function twinkle(out, age, shape, spots)
  local n = #spots
  for i, s in ipairs(spots) do
    local p = cycle(age, i, n, 40)
    if p then
      out[#out + 1] = { shape, s[1], s[2], math.max(0, math.sin(p * math.pi)) }
    end
  end
end

--- What to draw `age` ticks into effect `kind`: { {shape, dx, dy, alpha}, ... }, dx / dy
--- the shape's centre from the top of the head (dy negative = up). Pure (tested).
function MoodFx.particles(kind, age)
  age = math.max(0, math.floor(tonumber(age) or 0))
  local out = {}
  if kind == "hearts" then
    rising(out, age, "heart", 5, 12, 2)
  elseif kind == "love" then
    rising(out, age, "heart", 5, 12, 2)
    twinkle(out, age, "sparkle", { { -10, -2 }, { 10, -6 } })
  elseif kind == "notes" then
    rising(out, age, "note", 6, 10, 3)
  elseif kind == "sparkles" then
    twinkle(out, age, "sparkle", { { -9, -1 }, { 0, -8 }, { 9, -3 } })
  elseif kind == "exclaim" then
    local bob = (age % 30 < 15) and 0 or -1
    out[#out + 1] = { "exclaim", 0, -4 + bob, math.min(1, age / 8) }
  elseif kind == "rain" then
    local bob = (age % 48 < 24) and 0 or -1
    out[#out + 1] = { "cloud", 0, -6 + bob, math.min(1, age / 12) }
    for i = 1, 3 do
      local p = cycle(age, i, 3, 24)
      if p then out[#out + 1] = { "raindrop", -3 + (i - 1) * 3, -2 + 6 * p, 1 - p } end
    end
  elseif kind == "tears" then
    for i = 1, 2 do
      local p = cycle(age, i, 2, 40)
      if p then out[#out + 1] = { "tear", (i == 1) and -5 or 5, 3 + 6 * p, fadeInOut(p, 0.15, 0.4) } end
    end
  elseif kind == "anger" then
    local on = (age % 24) < 16
    out[#out + 1] = { "anger", 7, -5, on and 1 or 0.35 }
  elseif kind == "sweat" then
    for i = 1, 2 do
      local p = cycle(age, i, 2, 48)
      if p then out[#out + 1] = { "sweat", (i == 1) and 7 or -7, 1 + 3 * p, fadeInOut(p, 0.15, 0.35) } end
    end
  elseif kind == "zzz" then
    for i = 1, 3 do
      local p = cycle(age, i, 3, 72)
      if p then out[#out + 1] = { "zee", 4 + 6 * p, -2 - 12 * p, fadeInOut(p, 0.15, 0.35) } end
    end
  elseif kind == "bubbles" then
    rising(out, age, "bubble", 6, 10, 1)
  elseif kind == "flame" then
    for i, x in ipairs({ -7, 7 }) do
      local flick = ((age + i * 5) % 10 < 5) and 0 or -1
      out[#out + 1] = { "flame", x, -2 + flick, 0.75 + 0.25 * math.sin((age + i * 9) * 0.5) }
    end
  elseif kind == "sparks" then
    for i, s in ipairs({ { -8, -2 }, { 8, -4 } }) do
      local on = ((age + i * 7) % 18) < 6
      if on then out[#out + 1] = { "spark", s[1], s[2], 1 } end
    end
  elseif kind == "snow" then
    for i = 1, 3 do
      local p = cycle(age, i, 3, 80)
      if p then out[#out + 1] = { "snow", -9 + (i - 1) * 9 + math.sin(p * math.pi * 2), -10 + 12 * p, fadeInOut(p, 0.2, 0.3) } end
    end
  end
  return out
end

-- ------------------------------------------------------------------ drawing
local images = {} -- shape name -> Image (false: no image support)

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

local function drawShape(g, name, x0, y0, alpha)
  local img = imageFor(name)
  if img then
    g.setColor(1, 1, 1, alpha)
    g.draw(img, x0, y0)
    return
  end
  local s = SHAPES[name]
  for row, line in ipairs(s.rows) do
    for col, v in ipairs(line) do
      local c = s.colours[v]
      if c then
        g.setColor(c[1], c[2], c[3], alpha)
        g.rectangle("fill", x0 + col - 1, y0 + row - 1, 1, 1)
      end
    end
  end
end

--- The effect as one field actor: head top centred at world (x, y), sorted at `sortY`
--- (in front of the partner), drawn over the map's upper layer.
function MoodFx.actor(kind, age, x, y, sortY, alphaMul)
  local parts = MoodFx.particles(kind, age)
  return {
    kind = "ow_mood_fx", elevation = 3, oamPriority = 1, sortY = sortY, x = x, y = y,
    i = 99600,
    draw = function(_, camX, camY)
      if not (love and love.graphics and love.graphics.rectangle) then return end
      local g = love.graphics
      local r, gg, b, a = g.getColor()
      for _, p in ipairs(parts) do
        local s = SHAPES[p[1]]
        local alpha = p[4] * (alphaMul or 1)
        if s and alpha > 0 then
          local w, h = #s.rows[1], #s.rows
          drawShape(g, p[1], math.floor(x + p[2] - w / 2 - camX), math.floor(y + p[3] - h / 2 - camY), alpha)
        end
      end
      g.setColor(r, gg, b, a)
    end,
  }
end

return MoodFx
