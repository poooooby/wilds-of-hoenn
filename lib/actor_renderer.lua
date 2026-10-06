-- Draws one wild Pokemon as a 6-frame walker sheet via love quads. Gen 3's
-- field already renders true-color (no DMG/GBC palette machinery to
-- thread through, unlike Gen 1Recomp's SpriteRenderer) -- see
-- lib/engine_patch.lua's `collectActors` wrap for the actor contract this
-- implements: draw(x, y, camX, camY, facing, walkPhase, stepFlip).
--
-- Frame layout matches Wilds of Kanto Revival's sheets exactly (both
-- styles): 6 frames stacked vertically -- stand down/up/left, walk
-- down/up/left -- right mirrors left. Frame WIDTH is the whole sheet's
-- width; frame HEIGHT is the sheet's height / 6. Poke Followers / GSC is
-- always 16x16 per frame; HGSS / PokeMMO ("True Size") varies per species
-- (e.g. Bulbasaur 24x24, Pikachu 18x18, not necessarily square) -- this
-- renderer reads the real loaded image's dimensions rather than assuming
-- a fixed size, and anchors every sprite the same way Gen 3's own native
-- OW sprites anchor a variable-size OAM shape to a 16px cell
-- (ow_sprites.lua: centered horizontally, feet aligned to the cell's
-- bottom edge) -- so a bigger-than-one-tile HGSS sprite extends upward
-- from its feet instead of being squashed into 16x16 or drawn off-center.
local V = ...
local SpriteSource = V.require("sprite_source")
local SpriteAtlas = V.require("sprite_atlas")

local ActorRenderer = {}
ActorRenderer.__index = ActorRenderer

local CELL = 16
local FRAME_COUNT = 6

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

--- Pure screen-offset math for a `frameW x frameH` sprite anchored to a
--- CELL-px tile the same way Gen 3's native OW sprites are (see header):
--- centered horizontally, feet (bottom edge) flush with the cell's
--- bottom. Split out for testing without love.graphics.
function ActorRenderer.anchorOffset(frameW, frameH)
  return (CELL - frameW) / 2, CELL - frameH
end

--- Pure draw-position math for love.graphics.draw(image, quad, drawX, drawY,
--- 0, flipX, 1): the (drawX, drawY, flipX) to pass so a `frameW x frameH`
--- frame lands centered-and-feet-anchored (anchorOffset above) REGARDLESS
--- of facing, including when mirrored. Split out from draw() so the
--- left/right mirror math is directly testable without love.graphics --
--- this is exactly the formula that was wrong (frameW - anchorX instead
--- of anchorX + frameW) until a reported snap on every left<->right turn
--- caught it; see the comment on the return line for why.
function ActorRenderer.drawOffset(facing, frameW, frameH)
  local anchorX, anchorY = ActorRenderer.anchorOffset(frameW, frameH)
  if facing ~= "right" then
    return anchorX, anchorY, 1
  end
  -- love.graphics.draw with sx=-1 paints quad-local x in [0,frameW] onto
  -- screen x in [drawX-frameW, drawX] -- it runs BACKWARDS from drawX, the
  -- mirror of the unflipped [drawX, drawX+frameW] span -- so matching the
  -- unflipped span's horizontal center needs drawX = anchorX + frameW,
  -- not frameW - anchorX (those only happen to agree when frameW == CELL,
  -- i.e. for every Poke Followers/GSC frame, which is why this stayed
  -- invisible until HGSS/PokeMMO's non-16-wide frames exposed it).
  return anchorX + frameW, anchorY, -1
end

local imageCache = setmetatable({}, { __mode = "v" })
local quadCache = {} -- [path] = { [frameIndex] = quad }

--- A repo checkout (or any build before the atlas is generated) keeps the
--- real per-file sheets, so those are always tried FIRST -- this mod's
--- behaviour is identical with or without an atlas present as long as
--- the real files are there. A release build strips the per-file sheets
--- (scripts/build-mod.py, atlas mode) and ships assets/atlas/ instead, so
--- when the real-file attempts fail, SpriteAtlas.image is the fallback
--- that makes the game unaware anything changed.
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
  if not img and mod and SpriteAtlas.installed() then
    local ok, loaded = pcall(SpriteAtlas.image, mod, path)
    if ok then img = loaded end
  end
  if img then imageCache[path] = img end
  return img
end

local function quadFor(path, image, frameIndex)
  local perPath = quadCache[path]
  if not perPath then
    perPath = {}
    quadCache[path] = perPath
  end
  local q = perPath[frameIndex]
  if q then return q end
  if not (love and love.graphics and love.graphics.newQuad) then return nil end
  local iw, ih = image:getDimensions()
  local frameH = ih / FRAME_COUNT
  q = love.graphics.newQuad(0, frameIndex * frameH, iw, frameH, iw, ih)
  perPath[frameIndex] = q
  return q
end

--- `dex` = national dex number (never engine-internal species id or
--- display name -- see lib/engine_patch.lua). `style` is
--- SpriteSource.STYLE_FOLLOWERS (default) or SpriteSource.STYLE_POKEMMO.
function ActorRenderer.new(mod, dex, shiny, style)
  return setmetatable({
    mod = mod, dex = dex, shiny = shiny and true or false,
    style = style or SpriteSource.DEFAULT_STYLE, silhouette = false,
  }, ActorRenderer)
end

--- Resolved sheet path for this actor's current dex/shiny/style, or nil if
--- no art is installed for it (draw() then skips silently -- a missing
--- sheet never crashes the field renderer).
function ActorRenderer:imagePath()
  return SpriteSource.pathFor(self.mod, self.dex, self.shiny, self.style)
end

function ActorRenderer:draw(x, y, camX, camY, facing, walkPhase, _stepFlip)
  local path = self:imagePath()
  if not path then return end
  local image = loadImage(self.mod, path)
  if not image then return end
  local quad = quadFor(path, image, ActorRenderer.frameIndexFor(facing, walkPhase))
  if not quad then return end

  local _qx, _qy, frameW, frameH = quad:getViewport()
  local drawX, drawY, flipX = ActorRenderer.drawOffset(facing, frameW, frameH)

  if self.silhouette then
    -- Multiply-tint to black, keeping the sheet's own alpha -- no pixel
    -- remap needed: Gen 3's world already draws true-color, unshaded.
    love.graphics.setColor(0, 0, 0, 1)
  end
  love.graphics.draw(image, quad, (x - camX) + drawX, (y - camY) + drawY, 0, flipX, 1)
  if self.silhouette then
    love.graphics.setColor(1, 1, 1, 1)
  end
end

return ActorRenderer
