-- A small floating label in the overworld ("Found Potion!", a battle's "+EXP").
--
-- It is a field actor (the same shape lib/grass_cover.lua appends), so it sorts
-- with everything else and scrolls with the camera. The text is drawn with the
-- engine's own dialogue font (through EnginePatch, the only engine touchpoint);
-- without the font it quietly draws nothing.
--
-- Two looks, by what the label says (`PopupText.styleFor`):
--   bubble  "Found X!", "+5 EXP", "New move ready!" (and anything else): a white rounded
--           speech bubble with a dark outline and a little tail pointing down at the Pokemon.
--   level   "Lv.12!": no plate -- rainbow letters, each rising and falling in a wave, the
--           colours shifting along the word and over time, over a soft glow that grows in
--           and out.
-- The Game Boy games keep the classic light plate (outline + white fill) for every label: no
-- animation.
--
-- Plates and letters are painted ONCE into tiny offscreen canvases (1 canvas pixel = 1
-- game pixel) drawn like any sprite, so they land exactly the same at every window size,
-- density and scaling on every platform. (The engine's small font draws each 8px glyph in
-- the bottom half of a 16px cell and leaves stray grey pixels in the empty top half: the
-- canvas edge clips those natively. A scissor rectangle was tried for that and drifted on
-- Android, where the window is scaled differently from the game canvas.) Rainbow letters are
-- baked in the font's white and tinted per frame. If no canvas can be made, everything is
-- drawn directly instead.
local V = ...
local EnginePatch = V.require("engine_patch")

local PopupText = {}

local PAD = 2
local FONT = { small = true } -- the engine's small dialogue face, dark
local FONT_WHITE = { small = true, colorName = "WHITE" } -- ... white (rainbow letters, tinted)
local PLATE_H = 10
local TAIL_H = 3
-- a rounded body: how far each of its top (and, mirrored, bottom) rows is set in
local OUTER = { 2, 1 }
local INNER = { 1 }
local BUBBLE = { fill = { 1, 1, 1 }, line = { 0.16, 0.17, 0.22 } }
local LEVEL_GLOW = { 1, 0.95, 0.8 }

--- "bubble" | "level" for a label's text. Pure.
function PopupText.styleFor(text)
  text = tostring(text or "")
  if text:find("^Lv") then return "level" end
  return "bubble"
end

-- The Game Boy font draws dark only: the classic light plate there.
local function classic()
  return EnginePatch.fontLayout ~= nil and EnginePatch.fontLayout() == "gb"
end
PopupText._classic = classic

-- The small face draws its glyphs lower in a 16px cell than the pen position says,
-- so the pen has to sit this much above where the text should appear. Ruby /
-- Sapphire / Emerald put the 8px glyphs in the BOTTOM half of the cell; FireRed /
-- LeafGreen's small sheet (latin_small_fg.rgba) has them on cell rows 4-10 (11
-- with the shadow), so the RSE drop pushed the text up out of the plate and cut
-- off its top. A drop of 4 puts that row 4 on the plate's second pixel row.
local SMALL_FACE_DROP = { rs = 8, frlg = 4 }

-- an unknown layout (no engine font yet) keeps the Ruby / Sapphire / Emerald drop
local function faceDrop()
  local layout = EnginePatch.fontLayout and EnginePatch.fontLayout()
  if layout == nil or layout == "rs" then return SMALL_FACE_DROP.rs end
  return SMALL_FACE_DROP.frlg
end
PopupText._faceDrop = faceDrop
-- The small face's space character draws a stray glyph, so words are drawn one
-- at a time with a plain gap between them instead.
local WORD_GAP = 3
local CACHE_MAX = 64

--- Splits `text` at spaces. Pure (tested).
function PopupText.words(text)
  local out = {}
  for w in tostring(text):gmatch("%S+") do out[#out + 1] = w end
  return out
end

-- word widths, the total text width, and the summed raw widths (0 = no font)
local function measure(words)
  local widths, width, measured = {}, 0, 0
  for i, word in ipairs(words) do
    widths[i] = EnginePatch.measureText(word, FONT)
    measured = measured + widths[i]
    width = width + widths[i] + (i > 1 and WORD_GAP or 0)
  end
  return widths, width, measured
end

-- ------------------------------------------------------------------ motion (pure)

local function hsv(h, s, v)
  local i = math.floor(h * 6) % 6
  local f = h * 6 - math.floor(h * 6)
  local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
  if i == 0 then return v, t, p elseif i == 1 then return q, v, p elseif i == 2 then return p, v, t
  elseif i == 3 then return p, q, v elseif i == 4 then return t, p, v end
  return v, p, q
end

--- The level-up letters `age` ticks in: per character { ch, dy, r, g, b } -- a hue that
--- shifts along the word and over time, each letter rising and falling in turn. Spaces are
--- left out (`gap` = true on the letter after one). Pure.
function PopupText.rainbowLetters(text, age)
  local out = {}
  age = tonumber(age) or 0
  local chars = {}
  for ch in tostring(text):gmatch(".") do chars[#chars + 1] = ch end
  local n = #chars
  local gap = false
  for i, ch in ipairs(chars) do
    if ch == " " then
      gap = true
    else
      local r, g, b = hsv((age / 120 + (i - 1) / math.max(1, n)) % 1, 0.65, 1)
      out[#out + 1] = { ch = ch, dy = -math.sin(age / 14 + (i - 1) * 0.7) * 2, r = r, g = g, b = b, gap = gap }
      gap = false
    end
  end
  return out
end

--- The level-up glow `age` ticks in: { grow (px past the text, 1..3), alpha (0.10..0.28) }.
function PopupText.glow(age)
  local k = 0.5 - 0.5 * math.cos((tonumber(age) or 0) / 80 * math.pi * 2)
  return { grow = 1 + 2 * k, alpha = 0.10 + 0.18 * k }
end

-- ------------------------------------------------------------------ painting

-- The plate's size around text `width` px wide: its canvas (cw, ch), the text's pen from the
-- canvas's top-left (tx, ty) and where the canvas sits from the label's anchor point (the
-- bottom centre: the tail's tip / the plate's bottom): ax (half its width), ay (its height).
local function geometry(width, style)
  if classic() then
    local cw = width + PAD * 2 + 2
    return { cw = cw, ch = PLATE_H + 2, tx = 1 + PAD, ty = 2, ax = math.floor(cw / 2), ay = PLATE_H + 2 }
  end
  local cw = width + PAD * 2 + 2
  local ch = PLATE_H + 2 + (style == "bubble" and TAIL_H or 0)
  return { cw = cw, ch = ch, tx = 1 + PAD, ty = 2, ax = math.floor(cw / 2), ay = ch }
end
PopupText._geometry = geometry

local function inset(list, y, h) return list[y + 1] or list[h - y] or 0 end

-- a rounded rect, row by row (opaque colours: each row one rectangle)
local function roundRect(g, x, y, w, h, insets)
  for row = 0, h - 1 do
    local s = inset(insets, row, h)
    if w - s * 2 > 0 then g.rectangle("fill", x + s, y + row, w - s * 2, 1) end
  end
end

-- Paints a plate of `geo` with its canvas top-left at (x, y), and the words on it.
local function paintPlate(x, y, geo, style, words, widths)
  local g = love.graphics
  local w, h = geo.cw, PLATE_H + 2
  if classic() then
    g.setColor(0, 0, 0, 1)
    g.rectangle("fill", x, y, w, h)
    g.setColor(1, 1, 1, 1)
    g.rectangle("fill", x + 1, y + 1, w - 2, h - 2)
  else
    local c = BUBBLE
    g.setColor(c.line[1], c.line[2], c.line[3], 1)
    roundRect(g, x, y, w, h, OUTER)
    g.setColor(c.fill[1], c.fill[2], c.fill[3], 1)
    roundRect(g, x + 1, y + 1, w - 2, h - 2, INNER)
    if style == "bubble" then
      -- the tail: an opening in the bottom edge, then 5 / 3 / 1 px down to its tip
      local mid = x + math.floor(w / 2)
      g.setColor(c.fill[1], c.fill[2], c.fill[3], 1)
      g.rectangle("fill", mid - 1, y + h - 1, 3, 1)
      g.rectangle("fill", mid - 1, y + h, 3, 1)
      g.rectangle("fill", mid, y + h + 1, 1, 1)
      g.setColor(c.line[1], c.line[2], c.line[3], 1)
      g.rectangle("fill", mid - 2, y + h, 1, 1)
      g.rectangle("fill", mid + 2, y + h, 1, 1)
      g.rectangle("fill", mid - 1, y + h + 1, 1, 1)
      g.rectangle("fill", mid + 1, y + h + 1, 1, 1)
      g.rectangle("fill", mid, y + h + 2, 1, 1)
    end
  end
  local penX = x + geo.tx
  for i, word in ipairs(words) do
    EnginePatch.drawText(word, penX, y + geo.ty - faceDrop(), FONT)
    penX = penX + widths[i] + WORD_GAP
  end
  g.setColor(1, 1, 1, 1)
end

local cache, cached = {}, 0

local function dropCache()
  for _, item in pairs(cache) do
    if item.canvas and item.canvas.release then pcall(item.canvas.release, item.canvas) end
  end
  cache, cached = {}, 0
end
PopupText._dropCache = dropCache

-- A canvas `w` x `h` with `paint()` drawn into it, or nil when canvases are unavailable.
local function bakeCanvas(w, h, paint)
  local g = love.graphics
  if not (g.newCanvas and g.setCanvas and g.push and g.pop and g.clear) then return nil end
  local ok, canvas = pcall(g.newCanvas, w, h, { dpiscale = 1 })
  if not (ok and canvas) then
    ok, canvas = pcall(g.newCanvas, w, h) -- older LOVE has no settings table
  end
  if not (ok and canvas) then return nil end
  if canvas.setFilter then canvas:setFilter("nearest", "nearest") end
  g.push("all") -- saves the target, transform, colour, shader, scissor and blend mode
  local painted = pcall(function()
    g.setCanvas(canvas)
    g.origin()
    if g.setScissor then g.setScissor() end
    if g.setShader then g.setShader() end
    g.setBlendMode("alpha")
    g.clear(0, 0, 0, 0)
    paint()
  end)
  g.pop()
  if not painted then return nil end
  return canvas
end

local function cached_(key, make)
  local hit = cache[key]
  if hit then return hit end
  if cached >= CACHE_MAX then dropCache() end
  local canvas = make()
  if canvas then
    cache[key] = { canvas = canvas }
    cached = cached + 1
    return cache[key]
  end
  return nil
end

local function plateFor(text, style, geo, words, widths)
  return cached_((classic() and "gb:" or style .. ":") .. text, function()
    return bakeCanvas(geo.cw, geo.ch, function() paintPlate(0, 0, geo, style, words, widths) end)
  end)
end

-- one character in the font's white, for tinting
local function glyphFor(ch, w)
  return cached_("ch:" .. ch, function()
    return bakeCanvas(w, PLATE_H, function()
      EnginePatch.drawText(ch, 0, 1 - faceDrop(), FONT_WHITE)
    end)
  end)
end

-- The level-up word centred over (sx, sy) (its bottom), `age` ticks in.
local function drawLevel(text, sx, sy, age)
  local g = love.graphics
  local letters = PopupText.rainbowLetters(text, age)
  local total = 0
  for _, l in ipairs(letters) do
    l.w = EnginePatch.measureText(l.ch, FONT)
    total = total + l.w + (l.gap and WORD_GAP or 0)
  end
  if total <= 0 then return end
  local left, top = sx - math.floor(total / 2), sy - PLATE_H
  -- the glow: two soft rounded layers, growing in and out
  local gl = PopupText.glow(age)
  local grow = math.floor(gl.grow + 0.5)
  g.setColor(LEVEL_GLOW[1], LEVEL_GLOW[2], LEVEL_GLOW[3], gl.alpha * 0.6)
  roundRect(g, left - 2 - grow, top - grow, total + 4 + grow * 2, PLATE_H + grow * 2, OUTER)
  g.setColor(LEVEL_GLOW[1], LEVEL_GLOW[2], LEVEL_GLOW[3], gl.alpha)
  roundRect(g, left - 1, top + 1, total + 2, PLATE_H - 2, INNER)
  local x = left
  for _, l in ipairs(letters) do
    if l.gap then x = x + WORD_GAP end
    local y = top + math.floor(l.dy + 0.5)
    local glyph = glyphFor(l.ch, l.w)
    if glyph then
      g.setColor(l.r, l.g, l.b, 1)
      g.draw(glyph.canvas, x, y)
    else
      EnginePatch.drawText(l.ch, x, y + 1 - faceDrop(), { small = true,
        colors = { fg = { l.r, l.g, l.b, 1 }, shadow = { l.r * 0.45, l.g * 0.45, l.b * 0.45, 1 }, bg = { 0, 0, 0, 0 } } })
    end
    x = x + l.w
  end
  g.setColor(1, 1, 1, 1)
end

--- A field actor for `text` standing over the tile pixel (ox, oy) (the tile's
--- top-left), `lift` px above its top (the bubble's tail tip / the word's bottom); `age` =
--- ticks it has been showing (animates a level-up; nil = 0).
function PopupText.actor(text, ox, oy, elevation, lift, id, age)
  if type(text) ~= "string" or text == "" then return nil end
  lift = lift or 18
  age = tonumber(age) or 0
  local gx, gy = ox + 8, oy
  local style = PopupText.styleFor(text)
  return {
    kind = "follower_popup",
    elevation = elevation or 3,
    sortY = gy + 64, -- always in front of the sprites around it
    x = gx, y = gy,
    i = 90600 + (tonumber(id) or 0),
    style = style, lift = lift,
    draw = function(_, camX, camY)
      if not (love and love.graphics and love.graphics.rectangle) then return end
      local g = love.graphics
      local sx, sy = math.floor(gx - camX), math.floor(gy - camY - lift)
      local words = PopupText.words(text)
      local widths, width, measured = measure(words)
      if measured <= 0 then return end -- no engine font: draw nothing
      if style == "level" and not classic() then
        drawLevel(text, sx, sy, age)
        return
      end
      local geo = geometry(width, style)
      local px, py = sx - geo.ax, sy - geo.ay
      local plate = plateFor(text, style, geo, words, widths)
      if plate then
        g.setColor(1, 1, 1, 1)
        g.draw(plate.canvas, px, py)
      else
        paintPlate(px, py, geo, style, words, widths)
      end
      g.setColor(1, 1, 1, 1)
    end,
  }
end

return PopupText
