-- Draws one wild Pokemon as a true-color 16x96 walker sheet via love
-- quads. Gen 3's field already renders true-color (no DMG/GBC palette
-- machinery to thread through, unlike Gen 1Recomp's SpriteRenderer) --
-- see lib/engine_patch.lua's `collectActors` wrap for the actor contract
-- this implements: draw(x, y, camX, camY, facing, walkPhase, stepFlip).
--
-- Frame layout matches Wilds of Kanto Revival's walker sheets exactly
-- (lib/sprite_providers.lua there): 6 16x16 frames stacked vertically --
-- stand down/up/left, walk down/up/left -- right mirrors left.
local V = ...
local SpriteSource = V.require("sprite_source")

local ActorRenderer = {}
ActorRenderer.__index = ActorRenderer

local FRAME_W, FRAME_H, FRAME_COUNT = 16, 16, 6

-- facing -> { stand frame index, walk frame index }, 0-based (row in the
-- sheet). "right" reuses "left"'s frames and is mirrored at draw time.
local FRAME_INDEX = {
  down = { stand = 0, walk = 3 },
  up = { stand = 1, walk = 4 },
  left = { stand = 2, walk = 5 },
  right = { stand = 2, walk = 5 },
}

--- Pure frame-index lookup, split out from draw() so it is testable without
--- love.graphics. walkPhase truthy (1 or true) selects the walk frame.
function ActorRenderer.frameIndexFor(facing, walkPhase)
  local dir = FRAME_INDEX[facing] or FRAME_INDEX.down
  if walkPhase == 1 or walkPhase == true then return dir.walk end
  return dir.stand
end

local imageCache = setmetatable({}, { __mode = "v" })
local quadCache = {}

local function loadImage(mod, path)
  local cached = imageCache[path]
  if cached then return cached end
  local img
  if mod and mod.assets and type(mod.assets.image) == "function" then
    local ok, loaded = pcall(mod.assets.image, mod, path)
    if ok then img = loaded end
  end
  if not img and love and love.graphics and love.graphics.newImage then
    local ok, loaded = pcall(love.graphics.newImage, path)
    if ok then img = loaded end
  end
  if img then imageCache[path] = img end
  return img
end

local function quadFor(frameIndex)
  local q = quadCache[frameIndex]
  if q then return q end
  if not (love and love.graphics and love.graphics.newQuad) then return nil end
  q = love.graphics.newQuad(0, frameIndex * FRAME_H, FRAME_W, FRAME_H,
    FRAME_W, FRAME_H * FRAME_COUNT)
  quadCache[frameIndex] = q
  return q
end

--- `dex` = national dex number (never engine-internal species id or
--- display name -- see lib/national_dex.lua).
function ActorRenderer.new(mod, dex, shiny)
  return setmetatable({
    mod = mod, dex = dex, shiny = shiny and true or false, silhouette = false,
  }, ActorRenderer)
end

--- Resolved sheet path for this actor's current dex/shiny, or nil if no
--- art is installed for it (draw() then skips silently -- a missing sheet
--- never crashes the field renderer).
function ActorRenderer:imagePath()
  return SpriteSource.pathFor(self.mod, self.dex, self.shiny)
end

function ActorRenderer:draw(x, y, camX, camY, facing, walkPhase, _stepFlip)
  local path = self:imagePath()
  if not path then return end
  local image = loadImage(self.mod, path)
  if not image then return end
  local quad = quadFor(ActorRenderer.frameIndexFor(facing, walkPhase))
  if not quad then return end

  local flipX = (facing == "right") and -1 or 1
  local offsetX = (facing == "right") and FRAME_W or 0
  if self.silhouette then
    -- Multiply-tint to black, keeping the sheet's own alpha -- no pixel
    -- remap needed: Gen 3's world already draws true-color, unshaded.
    love.graphics.setColor(0, 0, 0, 1)
  end
  love.graphics.draw(image, quad, (x - camX) + offsetX, y - camY, 0, flipX, 1)
  if self.silhouette then
    love.graphics.setColor(1, 1, 1, 1)
  end
end

return ActorRenderer
