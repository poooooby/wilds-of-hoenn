-- A small floating label in the overworld ("Found Potion!", a battle's "+EXP").
--
-- It is a field actor (the same shape lib/grass_cover.lua appends), so it sorts
-- with everything else and scrolls with the camera. The text is drawn with the
-- engine's own dialogue font (through EnginePatch, the only engine touchpoint)
-- on a small plate; without the font it quietly draws nothing.
--
-- The label is painted ONCE into a tiny offscreen canvas (1 canvas pixel = 1
-- game pixel) and that canvas is drawn like any sprite, so it lands exactly the
-- same at every window size, density and scaling on every platform. (The engine's
-- small font draws each 8px glyph in the bottom half of a 16px cell and leaves
-- stray grey pixels in the empty top half: the canvas edge clips those natively.
-- A scissor rectangle was tried for that and drifted on Android, where the
-- window is scaled differently from the game canvas.) If no canvas can be made,
-- the plate and text are drawn directly instead.
local V = ...
local EnginePatch = V.require("engine_patch")

local PopupText = {}

local PAD = 2
local FONT = { small = true } -- the engine's small dialogue face
local PLATE_H = 10
-- The small face draws its 8px glyphs in the BOTTOM half of a 16px cell, so the
-- pen position has to sit this much above where the text should appear.
local SMALL_FACE_DROP = 8
-- The small face's space character draws a stray glyph, so words are drawn one
-- at a time with a plain gap between them instead.
local WORD_GAP = 3
local CACHE_MAX = 48

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

-- Paints the plate (1px black outline, white fill) with its top-left at (px, py)
-- and the words on it, in whatever the current target and transform are.
local function paintLabel(px, py, w, h, words, widths)
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", px - 1, py - 1, w + 2, h + 2)
  g.setColor(1, 1, 1, 1)
  g.rectangle("fill", px, py, w, h)
  local penX = px + PAD
  for i, word in ipairs(words) do
    EnginePatch.drawText(word, penX, py + 1 - SMALL_FACE_DROP, FONT)
    penX = penX + widths[i] + WORD_GAP
  end
  g.setColor(1, 1, 1, 1)
end

local cache, cached = {}, 0

local function dropCache()
  for _, label in pairs(cache) do
    if label.canvas and label.canvas.release then pcall(label.canvas.release, label.canvas) end
  end
  cache, cached = {}, 0
end
PopupText._dropCache = dropCache

-- The label as a canvas: { canvas, w, h } (w, h = the plate, the canvas is 2px
-- bigger each way for the outline), or nil when canvases are unavailable.
local function bake(text, words, widths, width)
  local g = love.graphics
  if not (g.newCanvas and g.setCanvas and g.push and g.pop and g.clear) then return nil end
  local w, h = width + PAD * 2, PLATE_H
  local ok, canvas = pcall(g.newCanvas, w + 2, h + 2, { dpiscale = 1 })
  if not (ok and canvas) then
    ok, canvas = pcall(g.newCanvas, w + 2, h + 2) -- older LOVE has no settings table
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
    paintLabel(1, 1, w, h, words, widths)
  end)
  g.pop()
  if not painted then return nil end
  return { canvas = canvas, w = w, h = h }
end

local function labelFor(text, words, widths, width)
  local hit = cache[text]
  if hit then return hit end
  if cached >= CACHE_MAX then dropCache() end
  local label = bake(text, words, widths, width)
  if label then
    cache[text] = label
    cached = cached + 1
  end
  return label
end

--- A field actor for `text` standing over the tile pixel (ox, oy) (the tile's
--- top-left), `lift` px above its top.
function PopupText.actor(text, ox, oy, elevation, lift, id)
  if type(text) ~= "string" or text == "" then return nil end
  lift = lift or 18
  local gx, gy = ox + 8, oy
  return {
    kind = "follower_popup",
    elevation = elevation or 3,
    sortY = gy + 64, -- always in front of the sprites around it
    x = gx, y = gy,
    i = 90600 + (tonumber(id) or 0),
    draw = function(_, camX, camY)
      if not (love and love.graphics and love.graphics.rectangle) then return end
      local sx, sy = math.floor(gx - camX), math.floor(gy - camY - lift)
      local words = PopupText.words(text)
      local widths, width, measured = measure(words)
      if measured <= 0 then return end -- no engine font: draw nothing
      local w, h = width + PAD * 2, PLATE_H
      local px, py = sx - math.floor(w / 2), sy - h
      local label = labelFor(text, words, widths, width)
      if label then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(label.canvas, px - 1, py - 1)
      else
        paintLabel(px, py, w, h, words, widths)
      end
    end,
  }
end

return PopupText
