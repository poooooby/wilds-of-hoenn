-- Portrait box for the engine's dialogue messages: a 40x40 PMDCollab
-- portrait (one emotion of one species) drawn just above the left of the
-- dialogue frame whenever a message is open.
--
-- The game's message box has no picture slot, so lib/engine_patch.lua's
-- `messageDraw` hook calls PortraitUI:draw() right after Message.draw() has
-- painted the frame and text; this module only decides WHAT to draw and WHERE
-- (the 240x160 canvas, 1:1 pixels, nothing scaled). It draws nothing unless a
-- portrait was set with show()/say() AND a message is open -- the moment the
-- message closes the portrait clears itself, so a stray show() can never
-- leave a picture on screen.
--
--   portraitUI:say("Hello!", { dex = 252, shiny = false, emotion = "Happy",
--                              done = function() end })
--   portraitUI:setEmotion("Joyous")   -- change the face between messages
--
-- Art: assets/pmd/portraits/<dex>-<normal|shiny>.png + portraits.json
-- (tools/generate_pmd_sprites.py); an emotion a species lacks falls back to
-- its Normal face, and one with no portraits at all draws nothing (the
-- message still shows).
local V = ...
local Config = V.require("config")
local EnginePatch = V.require("engine_patch")
local SpriteSource = V.require("sprite_source")
local FormSource = V.require("form_source")
local ActorRenderer = V.require("actor_renderer")
local MonMood = V.require("mon_mood")

local PortraitUI = {}
PortraitUI.__index = PortraitUI

local TILE = 8
local GAP = 2 -- px between the portrait plate and the dialogue frame

--- Top-left (canvas px) of a `size`-px portrait: aligned with the dialogue
--- text window's left edge, sitting just above the frame (which starts one
--- tile above the text window). Pure; split out for testing. `window` =
--- { left, top } in tiles (defaults match the standard dialogue window).
function PortraitUI.placement(window, size)
  local left = window and window.left or 2
  local top = window and window.top or 15
  return left * TILE + (Config.PORTRAIT_X or 0),
         (top - 1) * TILE - size - GAP + (Config.PORTRAIT_Y or 0)
end

function PortraitUI.new(mod)
  return setmetatable({ mod = mod, dex = nil, shiny = false, emotion = "Normal" }, PortraitUI)
end

--- Choose the portrait to show with the next/current message.
function PortraitUI:show(dex, shiny, emotion)
  self.dex, self.shiny, self.emotion = dex, shiny and true or false, emotion or "Normal"
end

--- Show a party Pokemon's own portrait with the emotion its state calls for
--- (lib/mon_mood.lua: HP, status, friendship). `emotion` overrides the
--- derived one (e.g. "Determined" for a Play action). Returns false when the
--- mon has no national dex number to look art up by.
function PortraitUI:showMon(mon, emotion)
  local dex = type(mon) == "table" and FormSource.artKeyFor(self.mod, mon.species or mon.speciesId) or nil
  if not dex then return false end
  local shiny = false
  if mon.personality ~= nil then
    shiny = EnginePatch.isShiny(mon.personality, tonumber(mon.otId), tonumber(mon.otSecretId))
  end
  self:show(dex, shiny, emotion or MonMood.emotionFor(mon))
  return true
end

--- Re-derives the face from the same mon after its state changed (e.g.
--- happiness went up) without reopening anything.
function PortraitUI:refreshMon(mon)
  if self.dex and type(mon) == "table" then self:setEmotion(MonMood.emotionFor(mon)) end
end

function PortraitUI:setEmotion(emotion)
  self.emotion = emotion or "Normal"
end

function PortraitUI:clear()
  self.dex = nil
end

function PortraitUI:isActive()
  return self.dex ~= nil
end

--- Opens a dialogue message with a portrait. opts: `mon` (a party mon: its
--- own species/shininess and a face derived from its state) OR `dex` +
--- `shiny`; `emotion` (overrides the derived/default face); stay (keep the box up, e.g. for a menu under
--- it), done (called when the message closes). The portrait clears when the
--- message does. Returns true when the message was shown.
function PortraitUI:say(text, opts)
  opts = opts or {}
  if opts.mon then
    self:showMon(opts.mon, opts.emotion)
  elseif opts.dex then
    self:show(opts.dex, opts.shiny, opts.emotion)
  end
  local userDone = opts.done
  local shown = EnginePatch.showMessage(text, {
    stay = opts.stay,
    done = function(...)
      if not opts.stay then self:clear() end
      if userDone then return userDone(...) end
    end,
  })
  if not shown then self:clear() end
  return shown
end

local quadCache = {} -- [path] = { [column] = quad }

local function quadFor(path, image, column, size)
  local perPath = quadCache[path]
  if not perPath then
    perPath = {}
    quadCache[path] = perPath
  end
  local q = perPath[column]
  if q then return q end
  if not (love and love.graphics and love.graphics.newQuad) then return nil end
  local iw, ih = image:getDimensions()
  q = love.graphics.newQuad(column * size, 0, size, ih, iw, ih)
  perPath[column] = q
  return q
end

--- Called by the messageDraw hook after every Message.draw(). Draws nothing
--- without a portrait, an open message or art.
function PortraitUI:draw()
  if not self.dex then return end
  if not EnginePatch.isMessageOpen() then
    self:clear()
    return
  end
  local key = SpriteSource.portraitKey(self.mod, self.dex)
  local info = SpriteSource.portraitInfo(self.mod, key)
  local path, column = SpriteSource.portraitCell(info, key, self.shiny, self.emotion)
  if not path then return end
  local image = ActorRenderer.loadImage(self.mod, path)
  if not image then return end
  local size = info.size
  local quad = quadFor(path, image, column, size)
  if not quad then return end

  local x, y = PortraitUI.placement(EnginePatch.dialogueWindow(), size)
  love.graphics.setColor(0, 0, 0, 0.85) -- plate, so the face reads on any map
  love.graphics.rectangle("fill", x - 1, y - 1, size + 2, size + 2)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(image, quad, x, y)
end

return PortraitUI
