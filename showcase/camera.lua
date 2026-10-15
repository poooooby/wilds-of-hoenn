-- Showcase camera: smooth pans, zooms and subject tracking for the trailer reel
-- (showcase/director.lua). Not part of the mod: it drives the engine from a
-- POKEPORT_DRIVER script.
--
-- Pan: the Gen 3 field centres its view on the player plus FieldView.cameraPanX/Y
-- (world px, the engine's own pan used by scripted camera moves). The camera keeps
-- a float pan; the engine gets the whole pixels, the fraction is applied when the
-- frame is drawn to the window, so a slow pan glides instead of stepping.
-- Zoom: the engine's own survey zoom (src.render.Zoom: whole steps, re-rendered
-- crisp) for the base framing, plus a smooth post zoom about the window centre:
-- while it is not 1 (or a pan fraction is pending), love.draw renders the frame
-- into a window-sized canvas -- "the screen" (setCanvas()) is pointed at that canvas
-- for the duration -- and draws it scaled.
local Camera = {}
Camera.__index = Camera

local FieldView = require("src.core.game3.field_view")
local Player = require("src.core.game3.player")
local Zoom = require("src.render.Zoom")

local EASE = {
  linear = function(t) return t end,
  inout = function(t) return t * t * (3 - 2 * t) end,
  out = function(t) return 1 - (1 - t) * (1 - t) end,
  ["in"] = function(t) return t * t end,
  -- a slow, film-like start and stop
  smooth = function(t) return t * t * t * (t * (t * 6 - 15) + 10) end,
}

function Camera.new()
  local self = setmetatable({ panX = 0, panY = 0, zoom = 1, tweens = {}, target = nil }, Camera)
  self:install()
  return self
end

-- the window px one world px covers at the current engine zoom (for the pan fraction)
local function worldScale()
  local ok, Renderer = pcall(require, "src.render.Renderer")
  if not ok or not Renderer or not Renderer.fitScale then return nil end
  local okS, s = pcall(function() return Zoom.scale(Renderer:fitScale()) end)
  return okS and tonumber(s) or nil
end

--- The world px the view centres on with no pan (the player's tile centre).
function Camera.playerCentre()
  return (Player.px or 0) + 8, (Player.py or 0) + 8
end

--- Back to a plain view: no pan, no zoom, engine zoom FIT, no tracking.
function Camera:reset()
  self.panX, self.panY, self.zoom, self.tweens, self.target = 0, 0, 1, {}, nil
  self:engineZoom(0)
  self:apply()
end

--- The engine's survey zoom step (0 = FIT, 1 = IN1, -1 = OUT1 ...), set at once.
function Camera:engineZoom(step)
  local ok, Renderer = pcall(require, "src.render.Renderer")
  local S = ok and Renderer and Renderer.fitScale and Renderer:fitScale() or 1
  Zoom.offset = Zoom.clampOffset(step or 0, S)
end

--- Jump: { panX, panY (world px from the player's centre), zoom, at = {wx, wy} }.
function Camera:set(t)
  if t.at then self.panX, self.panY = t.at[1] - Camera.playerCentre(), t.at[2] - select(2, Camera.playerCentre()) end
  if t.panX then self.panX = t.panX end
  if t.panY then self.panY = t.panY end
  if t.zoom then self.zoom = t.zoom end
  self.tweens, self.target = {}, nil
  self:apply()
end

--- Glide to { panX, panY | at = {wx, wy} (a world point to centre), zoom } over
--- `frames` (default 120) with `ease` (smooth). Non-blocking: the director's wait
--- advances it. A move cancels tracking.
function Camera:move(t)
  local frames = math.max(1, t.frames or 120)
  local ease = EASE[t.ease or "smooth"] or EASE.smooth
  local px, py = t.panX, t.panY
  if t.at then
    local cx, cy = Camera.playerCentre()
    px, py = t.at[1] - cx, t.at[2] - cy
  end
  self.target = nil
  self.tweens = {
    { key = "panX", from = self.panX, to = px or self.panX },
    { key = "panY", from = self.panY, to = py or self.panY },
    { key = "zoom", from = self.zoom, to = t.zoom or self.zoom },
    frames = frames, t = 0, ease = ease,
  }
end

--- Keep `fn()` (-> world x, y) centred, easing toward it (`lag` 0..1 per frame, 0.08),
--- optionally also gliding the zoom to `zoom` over `frames`.
function Camera:track(fn, opts)
  opts = opts or {}
  self.target = { fn = fn, lag = opts.lag or 0.08 }
  if opts.zoom then
    self.tweens = { { key = "zoom", from = self.zoom, to = opts.zoom }, frames = opts.frames or 90, t = 0,
                    ease = EASE[opts.ease or "smooth"] }
  else
    self.tweens = {}
  end
end

--- Stop tracking (the view stays where it is).
function Camera:still() self.target = nil end

--- Is a glide still running?
function Camera:busy()
  return self.tweens.frames ~= nil and self.tweens.t < self.tweens.frames
end

--- One frame: tweens and tracking, then hand the pan to the engine.
function Camera:update()
  local tw = self.tweens
  if tw.frames and tw.t < tw.frames then
    tw.t = tw.t + 1
    local k = tw.ease(tw.t / tw.frames)
    for _, v in ipairs(tw) do self[v.key] = v.from + (v.to - v.from) * k end
  end
  if self.target then
    local ok, wx, wy = pcall(self.target.fn)
    if ok and wx and wy then
      local cx, cy = Camera.playerCentre()
      local lag = self.target.lag
      self.panX = self.panX + ((wx - cx) - self.panX) * lag
      self.panY = self.panY + ((wy - cy) - self.panY) * lag
    end
  end
  self:apply()
end

function Camera:apply()
  local ix, iy = math.floor(self.panX + 0.5), math.floor(self.panY + 0.5)
  FieldView.cameraPanX, FieldView.cameraPanY = ix, iy
  local s = worldScale()
  -- the leftover fraction of a world px, as window px (drawn shifted the other way)
  self.fracX = s and -(self.panX - ix) * s or 0
  self.fracY = s and -(self.panY - iy) * s or 0
end

-- ------- the post zoom -----------------------------------------------------------

function Camera:install()
  if self.installed or not (love and love.graphics) then return end
  self.installed = true
  local G = love.graphics
  local cam = self
  local inner = love.draw
  love.draw = function(...)
    local zoom = cam.zoom or 1
    local fx, fy = cam.fracX or 0, cam.fracY or 0
    if math.abs(zoom - 1) < 1e-4 and math.abs(fx) < 0.01 and math.abs(fy) < 0.01 then
      return inner(...)
    end
    local w, h = G.getDimensions()
    local c = cam.canvas
    if not c or c:getWidth() ~= w or c:getHeight() ~= h then
      if c then c:release() end
      c = G.newCanvas(w, h)
      c:setFilter("nearest", "nearest")
      cam.canvas = c
    end
    local realSet = G.setCanvas
    realSet(c)
    G.clear(0, 0, 0, 1)
    -- everything the frame draws "to the screen" lands on the canvas
    G.setCanvas = function(a, ...)
      if a == nil then return realSet(c) end
      return realSet(a, ...)
    end
    local ok, r1, r2 = pcall(inner, ...)
    G.setCanvas = realSet
    realSet()
    G.push("all")
    G.origin()
    G.setScissor()
    G.setShader()
    G.setBlendMode("alpha", "premultiplied")
    G.setColor(1, 1, 1, 1)
    G.clear(0, 0, 0, 1)
    -- scaled about the window centre, shifted by the pan's leftover fraction
    G.translate(w / 2, h / 2)
    G.scale(zoom, zoom)
    G.translate(-w / 2 + fx, -h / 2 + fy)
    G.draw(c, 0, 0)
    G.pop()
    if not ok then error(r1, 0) end
    return r1, r2
  end
end

Camera.EASE = EASE
return Camera
