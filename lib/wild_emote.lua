-- The emote over a startled / angry wild Pokemon (lib/wild_reactions.lua):
--   "!"     surprised -- the game's own exclamation bubble (the engine's
--           `exclamation_question_mark` field-effect sheet, frame 0, as over a trainer
--           who spotted the player);
--   "?"     puzzled   -- the same sheet's frame 1;
--   "anger" angry     -- a red anger mark drawn in code (Gen 3 has no anger icon).
-- It pops up with the engine bubble's own bounce (field_effects.lua: y velocity -5,
-- +1 a tick until it lands) and sits just above the Pokemon's head (renderer:headLift),
-- so no animation frame covers it. A plain field actor drawn after the map's upper
-- layer, never an image gen3-hd-sprites resizes. Without the engine sheet the "!" and
-- "?" are drawn in code too; without love.graphics (the tests) nothing is drawn.
local V = ...
local EnginePatch = V.require("engine_patch")

local WildEmote = {}

--- The bounce `age` ticks in, px (negative = up): the engine bubble's, landing after
--- about 10 ticks and resting at 0. Pure (tested).
function WildEmote.bounce(age)
  age = math.max(0, math.floor(tonumber(age) or 0))
  local y, vy = 0, -5
  for _ = 1, age do
    if y == 0 and vy > 0 then break end
    y = y + vy
    vy = vy + 1
    if y > 0 then y = 0 end
  end
  return y
end

-- the anger mark: four little curved strokes round an empty middle, like a throbbing vein
local ANGER = {
  { 0, 2, 2, 0, 0, 0, 2, 2, 0 },
  { 2, 1, 1, 2, 0, 2, 1, 1, 2 },
  { 2, 1, 2, 0, 0, 0, 2, 1, 2 },
  { 0, 2, 0, 0, 0, 0, 0, 2, 0 },
  { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  { 0, 2, 0, 0, 0, 0, 0, 2, 0 },
  { 2, 1, 2, 0, 0, 0, 2, 1, 2 },
  { 2, 1, 1, 2, 0, 2, 1, 1, 2 },
  { 0, 2, 2, 0, 0, 0, 2, 2, 0 },
}
local ANGER_COLOURS = { [1] = { 0.93, 0.16, 0.16 }, [2] = { 0.45, 0.04, 0.06 } }
-- code-drawn fallbacks for the bubble marks (a 5 x 9 glyph, white with a dark edge)
local BANG = {
  { 2, 2, 2 }, { 2, 1, 2 }, { 2, 1, 2 }, { 2, 1, 2 }, { 2, 1, 2 }, { 2, 2, 2 }, { 0, 0, 0 }, { 2, 2, 2 }, { 2, 1, 2 }, { 2, 2, 2 },
}
local QUERY = {
  { 0, 2, 2, 2, 0 }, { 2, 1, 1, 1, 2 }, { 2, 2, 0, 1, 2 }, { 0, 0, 2, 1, 2 }, { 0, 2, 1, 2, 0 },
  { 0, 2, 1, 2, 0 }, { 0, 2, 2, 2, 0 }, { 0, 2, 1, 2, 0 }, { 0, 2, 2, 2, 0 },
}
local GLYPH_COLOURS = { [1] = { 1, 1, 1 }, [2] = { 0.16, 0.16, 0.2 } }
WildEmote.ANGER, WildEmote.BANG, WildEmote.QUERY = ANGER, BANG, QUERY

local function drawShape(g, shape, colours, x0, y0)
  for row, line in ipairs(shape) do
    for col, v in ipairs(line) do
      local c = colours[v]
      if c then
        g.setColor(c[1], c[2], c[3], 1)
        g.rectangle("fill", x0 + col - 1, y0 + row - 1, 1, 1)
      end
    end
  end
end

local sheet -- the engine's bubble sheet (false: not available)
local function bubbleSheet()
  if sheet == nil then
    sheet = EnginePatch.fieldEffectSheet and EnginePatch.fieldEffectSheet("exclamation_question_mark", 16, 16, 2)
      or false
  end
  return sheet or nil
end

--- The emote `kind` ("!" | "?" | "anger") `age` ticks after it appeared, as a field actor
--- over a Pokemon standing on the tile whose top-left is (wx, wy), its head `lift` px above
--- the tile's ground line.
function WildEmote.actor(kind, age, wx, wy, lift, elevation, id)
  local cx = wx + 8
  local base = wy + 16 - (lift or 20) -- the emote's bottom edge
  local bob = WildEmote.bounce(age)
  return {
    kind = "ow_wild_emote", emote = kind,
    elevation = elevation or 3,
    oamPriority = 1, -- over roofs and tree crowns too, like the engine's own bubble
    sortY = wy + 18,
    x = cx, y = base + bob,
    i = 91800 + (tonumber(id) or 0),
    draw = function(_, camX, camY)
      if not (love and love.graphics and love.graphics.rectangle) then return end
      local g = love.graphics
      local r, gg, b, a = g.getColor()
      local bx, by = math.floor(cx - camX), math.floor(base + bob - camY)
      if kind == "anger" then
        drawShape(g, ANGER, ANGER_COLOURS, bx - 4, by - 9)
      else
        local s = bubbleSheet()
        local q = s and s.quads and s.quads[kind == "?" and 1 or 0]
        if q and s.image then
          g.setColor(1, 1, 1, 1)
          g.draw(s.image, q, bx - 8, by - 16)
        else
          local shape = kind == "?" and QUERY or BANG
          drawShape(g, shape, GLYPH_COLOURS, bx - math.floor(#shape[1] / 2), by - #shape)
        end
      end
      g.setColor(r, gg, b, a)
    end,
  }
end

return WildEmote
