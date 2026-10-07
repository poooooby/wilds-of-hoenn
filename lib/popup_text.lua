-- A small floating label in the overworld ("Found Potion!", a battle's "+EXP").
--
-- It is a field actor (the same shape lib/grass_cover.lua appends), so it sorts
-- with everything else and scrolls with the camera. The text is drawn with the
-- engine's own dialogue font (through EnginePatch, the only engine touchpoint)
-- on a small white plate; without the font it quietly draws nothing.
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

--- Splits `text` at spaces. Pure (tested).
function PopupText.words(text)
  local out = {}
  for w in tostring(text):gmatch("%S+") do out[#out + 1] = w end
  return out
end

--- A field actor for `text` standing over the tile pixel (ox, oy) (the tile's
--- top-left), `lift` px above its top, `age` ticks old. Fades out near the end
--- of `life` ticks by dropping the label early (the pixel font cannot alpha).
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
      local widths, width, measured = {}, 0, 0
      for i, word in ipairs(words) do
        widths[i] = EnginePatch.measureText(word, FONT)
        measured = measured + widths[i]
        width = width + widths[i] + (i > 1 and WORD_GAP or 0)
      end
      if measured <= 0 then return end -- no engine font: draw nothing
      local w, h = width + PAD * 2, PLATE_H
      local px, py = sx - math.floor(w / 2), sy - h
      love.graphics.setColor(0, 0, 0, 0.85)
      love.graphics.rectangle("fill", px - 1, py - 1, w + 2, h + 2)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", px, py, w, h)
      -- The small face's glyph cell is twice as tall as its glyphs and its empty
      -- half holds stray grey pixels; shifting the text up to sit in the plate
      -- puts that half above it. Clip the text to the plate so only the glyphs
      -- show. (A scissor ignores transforms, so map the plate's corners through
      -- the current transform first.)
      local g = love.graphics
      local clipped = g.setScissor and g.getScissor and g.transformPoint
      local sx0, sy0, sw0, sh0
      if clipped then
        sx0, sy0, sw0, sh0 = g.getScissor()
        local x1, y1 = g.transformPoint(px, py)
        local x2, y2 = g.transformPoint(px + w, py + h)
        g.setScissor(math.floor(math.min(x1, x2) + 0.5), math.floor(math.min(y1, y2) + 0.5),
          math.floor(math.abs(x2 - x1) + 0.5), math.floor(math.abs(y2 - y1) + 0.5))
      end
      local penX = px + PAD
      for i, word in ipairs(words) do
        EnginePatch.drawText(word, penX, py + 1 - SMALL_FACE_DROP, FONT)
        penX = penX + widths[i] + WORD_GAP
      end
      if clipped then g.setScissor(sx0, sy0, sw0, sh0) end
      love.graphics.setColor(1, 1, 1, 1)
    end,
  }
end

return PopupText
