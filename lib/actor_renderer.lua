-- Draws one wild Pokemon (or the follower) as a walker sheet via love
-- quads. Gen 3's field already renders true-color (no DMG/GBC palette
-- machinery to thread through, unlike Gen 1Recomp's SpriteRenderer) -- see
-- lib/engine_patch.lua's `collectActors` wrap for the actor contract this
-- implements: draw(x, y, camX, camY, facing, walkPhase, stepFlip).
--
-- One frame layout (HGSS / PokeMMO, SpriteSource.STYLE_POKEMMO):
--   "True Size": 18 frames, matching the
--   real Gen 3 player NPC's own layout (see tools/generate_true_size_18frame.py
--   and lib/sprite_source.lua) -- stand x3, walk-A/walk-B x3 directions,
--   run-base/run-A/run-B x3 directions. Frame size varies per species (e.g.
--   Bulbasaur 24x24, Pikachu 18x18, not necessarily square) -- this renderer
--   reads the real loaded image's dimensions rather than assuming a fixed
--   size, and anchors every sprite the same way Gen 3's own native OW
--   sprites anchor a variable-size OAM shape to a 16px cell
--   (ow_sprites.lua: centered horizontally, feet aligned to the cell's
--   bottom edge) -- so a bigger-than-one-tile HGSS sprite extends upward
--   from its feet instead of being squashed into 16x16 or drawn off-center.
--
-- `walkPhase` (draw()'s 6th argument) is not the old binary flag -- it is
-- one of the POSE_* enum values below, computed entirely by the caller
-- (lib/spawn_manager.lua, lib/follower_adapter.lua). This mod can never
-- rely on the engine's own `stepFlip` draw() parameter for A/B alternation:
-- src/core/game3/field_view.lua hardcodes stepFlip=false for every actor
-- that isn't the player itself, so A/B phase has to be tracked and carried
-- through `walkPhase` by whoever owns the entity.
local V = ...
local SpriteSource = V.require("sprite_source")
local SpriteAtlas = V.require("sprite_atlas")
local Config = V.require("config")
local RecallMath = V.require("recall_math")
local HdField = V.require("hd_field")

local ActorRenderer = {}
ActorRenderer.__index = ActorRenderer

local CELL = 16

local FRAME_COUNT_POKEMMO = 18

-- Pose enum: the caller computes one of these per draw() call.
ActorRenderer.POSE_STAND = "stand"
ActorRenderer.POSE_WALK_A = "walkA"
ActorRenderer.POSE_WALK_B = "walkB"
ActorRenderer.POSE_RUN_BASE = "runBase"
ActorRenderer.POSE_RUN_A = "runA"
ActorRenderer.POSE_RUN_B = "runB"

-- facing -> { pose -> 0-based frame index (row in the sheet) }. "right"
-- reuses "left"'s frames and is mirrored at draw time.
--
-- 18-frame styles (STYLE_POKEMMO): the full layout from
-- tools/generate_true_size_18frame.py's OUTPUT_FRAMES order.
local FRAME_INDEX_18 = {
  down = {
    stand = 0, walkA = 3, walkB = 4,
    runBase = 9, runA = 10, runB = 11,
  },
  up = {
    stand = 1, walkA = 5, walkB = 6,
    runBase = 12, runA = 13, runB = 14,
  },
  left = {
    stand = 2, walkA = 7, walkB = 8,
    runBase = 15, runA = 16, runB = 17,
  },
}
FRAME_INDEX_18.right = FRAME_INDEX_18.left

local FRAME_COUNT_TO_TABLE = {
  [FRAME_COUNT_POKEMMO] = FRAME_INDEX_18,
}

--- Pure frame-index lookup, split out from draw() so it is testable without
--- love.graphics. `pose` is one of the ActorRenderer.POSE_* constants (any
--- other value, including nil/0 -- the engine's own `a.walkPhase or 0`
--- fallback when an actor never set one -- resolves to POSE_STAND).
--- `frameCount` picks the layout (18); anything else falls back to it too.
function ActorRenderer.frameIndexFor(facing, pose, frameCount)
  local table_ = FRAME_COUNT_TO_TABLE[frameCount] or FRAME_INDEX_18
  local dir = table_[facing] or table_.down
  return dir[pose] or dir[ActorRenderer.POSE_STAND]
end

local IDLE_FLAP_SEQUENCE = { "walkA", "stand", "walkB", "stand" }

--- The pose a floating/flying species shows while standing still, `clock`
--- being its own idle tick counter: walkA, stand, walkB, stand, each held
--- `ticksPerPose` ticks. `stand` between the walk frames keeps the flap
--- readable even for a species whose walkA and walkB are close.
--- Pure, for testing without love.graphics.
function ActorRenderer.idleFlapPose(clock, ticksPerPose)
  ticksPerPose = ticksPerPose or 20
  if ticksPerPose < 1 then ticksPerPose = 1 end
  local i = math.floor((tonumber(clock) or 0) / ticksPerPose) % #IDLE_FLAP_SEQUENCE
  return IDLE_FLAP_SEQUENCE[i + 1]
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
  -- which is why this stayed invisible until non-16-wide frames exposed it).
  return anchorX + frameW, anchorY, -1
end

--- Pure "push back along facing" math, in pixels -- the single-follower
--- analog of Wilds of Kanto Revival's multi-trailer convoy spacing
--- (ControlEngine's own `behindOffset`): moves a draw position AWAY from
--- the direction currently faced, toward where the entity came from, so a
--- wider-than-one-tile (True Size) sprite doesn't visually overlap
--- whatever it's walking toward. `px` <= 0 is a no-op. Split out for
--- testing without love.graphics, same as anchorOffset/drawOffset above.
function ActorRenderer.behindOffset(facing, px)
  if not px or px == 0 then return 0, 0 end
  local dx = facing == "left" and 1 or facing == "right" and -1 or 0
  local dy = facing == "up" and 1 or facing == "down" and -1 or 0
  return dx * px, dy * px
end

--- Moves `cur` toward `target` by at most `maxStep` (never overshoots). Pure,
--- for easing the follower's pushback offset one logic tick at a time.
function ActorRenderer.approach(cur, target, maxStep)
  if cur == nil then return target end
  local d = target - cur
  if d > maxStep then return cur + maxStep end
  if d < -maxStep then return cur - maxStep end
  return target
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
  if img then
    imageCache[path] = img
    -- drawn at window resolution by gen3-hd-sprites when it is installed (lib/hd_field.lua)
    HdField.tag(mod, img, path)
  end
  return img
end

ActorRenderer.loadImage = loadImage -- shared with lib/pmd_renderer.lua

local function quadFor(path, image, frameIndex, frameCount)
  local perPath = quadCache[path]
  if not perPath then
    perPath = {}
    quadCache[path] = perPath
  end
  local q = perPath[frameIndex]
  if q then return q end
  if not (love and love.graphics and love.graphics.newQuad) then return nil end
  local iw, ih = image:getDimensions()
  local frameH = ih / frameCount
  q = love.graphics.newQuad(0, frameIndex * frameH, iw, frameH, iw, ih)
  perPath[frameIndex] = q
  return q
end

--- The frame count of the sheet layout (18 -- the only one left). Kept as a
--- function of `style` for the callers that always pass one.
function ActorRenderer.frameCountFor(_style)
  return FRAME_COUNT_POKEMMO
end

--- `dex` = national dex number (never engine-internal species id or
--- display name -- see lib/engine_patch.lua). `style` is
--- SpriteSource.STYLE_POKEMMO (the default and only ActorRenderer style).
--- `presentation` is SpriteSource.PRESENTATION_LAND (default), SWIMMING, or
--- LEVITATES -- which terrain-specific art pack to draw from (see
--- lib/sprite_source.lua).
function ActorRenderer.new(mod, dex, shiny, style, presentation)
  style = style or SpriteSource.DEFAULT_STYLE
  return setmetatable({
    mod = mod, dex = dex, shiny = shiny and true or false,
    style = style, presentation = presentation or SpriteSource.DEFAULT_PRESENTATION,
    silhouette = false,
    frameCount = ActorRenderer.frameCountFor(style),
    largePushback = 0,
  }, ActorRenderer)
end

--- Resolved sheet path for this actor's current dex/shiny/style/presentation,
--- or nil if no art is installed for it (draw() then skips silently -- a
--- missing sheet never crashes the field renderer).
function ActorRenderer:imagePath()
  return SpriteSource.pathFor(self.mod, self.dex, self.shiny, self.style, self.presentation)
end

--- The current frame's pixel WIDTH for this renderer's resolved art, or
--- nil if nothing is loaded yet (no art installed, or no love context in
--- a standalone test). Frames stack VERTICALLY in every sheet this
--- renderer draws (see module header), so this is simply the whole loaded
--- image's own width -- no frame-count division needed, unlike height.
--- lib/follower_adapter.lua uses this to size `largePushback`.
--- Visible height in px of one frame (for things floating above the sprite).
function ActorRenderer:frameHeight()
  local path = self:imagePath()
  if not path then return nil end
  local image = loadImage(self.mod, path)
  if not image then return nil end
  local _, h = image:getDimensions()
  return h / (self.frameCount or 18)
end

function ActorRenderer:frameWidth()
  local path = self:imagePath()
  if not path then return nil end
  local image = loadImage(self.mod, path)
  if not image then return nil end
  return (image:getDimensions())
end

--- The width the sprite is actually drawn at: the sheet's own width times the size
--- gen3-hd-sprites draws it at (Overworld Size x Species Sizes; 1 without that mod).
--- Spacing a follower out from the player goes by this, not by the sheet.
function ActorRenderer:visualWidth()
  local path = self:imagePath()
  local w = self:frameWidth()
  if not (path and w) then return w end
  return w * HdField.scaleOfPath(self.mod, path)
end

function ActorRenderer:draw(x, y, camX, camY, facing, walkPhase, _stepFlip)
  -- a follower action scene (lib/follower_actions.lua) overrides the facing
  -- and slides the sprite by a cosmetic pixel offset
  local act = self.act
  if act and act.facing then facing = act.facing end
  local path = self:imagePath()
  if not path then return end
  local image = loadImage(self.mod, path)
  if not image then return end
  -- The follower's renderer is drawn through a path this mod does not
  -- control the arguments of (src/world/game3/Follower.lua's `actor()`
  -- computes a fresh `walkPhase` of plain 0/1 every frame, and that's what
  -- reaches here) -- lib/follower_adapter.lua tracks its own A/B parity and
  -- running state and hands the real pose through `poseOverride` instead,
  -- since it owns this renderer instance directly. Wild-mon callers
  -- (lib/spawn_manager.lua) never set this, so they're unaffected and
  -- `walkPhase` there is already one of the POSE_* strings.
  local pose = self.poseOverride or walkPhase
  local frameIndex = ActorRenderer.frameIndexFor(facing, pose, self.frameCount)
  local quad = quadFor(path, image, frameIndex, self.frameCount)
  if not quad then return end

  local _qx, _qy, frameW, frameH = quad:getViewport()
  local drawX, drawY, flipX = ActorRenderer.drawOffset(facing, frameW, frameH)
  drawY = drawY + SpriteSource.bottomPadFor(path) -- baked-in bottom margin
  -- A follower's offset is eased tick-by-tick by lib/follower_adapter.lua
  -- (pushX/pushY) so a turn glides instead of snapping; anything that never
  -- sets those falls back to the instantaneous per-facing value.
  local pushX, pushY = self.pushX, self.pushY
  if pushX == nil or pushY == nil then
    pushX, pushY = ActorRenderer.behindOffset(facing, self.largePushback)
  end

  if act then pushX, pushY = pushX + (act.dx or 0), pushY + (act.dy or 0) end

  -- recalled into the player (a Battler out of strength): shrink and slide
  -- toward them; sinking into the ground: squash toward the feet
  local mul, tint = 1, nil
  local recall = self.recall
  if recall ~= nil and recall < 1 then
    if recall <= 0.02 then return end -- fully inside
    if self.recallX and self.recallY then
      x, y, mul = RecallMath.blend(recall, x, y, self.recallX, self.recallY, Config.PMD_RECALL_LIFT)
    else
      mul = RecallMath.ease(recall)
    end
    tint = 0.55 + 0.45 * mul
  end
  local sink = act and tonumber(act.sink) or 0
  if sink >= 1 then return end
  local flash = act and tonumber(act.flash) or 0
  if flash > 0 then tint = math.min(tint or 1, 1 - 0.6 * math.min(1, flash)) end

  if self.silhouette then
    -- Multiply-tint to black, keeping the sheet's own alpha -- no pixel
    -- remap needed: Gen 3's world already draws true-color, unshaded.
    love.graphics.setColor(0, 0, 0, 1)
  elseif tint then
    love.graphics.setColor(1, tint, tint, 1)
  end
  if mul == 1 and sink <= 0 then
    love.graphics.draw(image, quad, (x - camX) + drawX + pushX, (y - camY) + drawY + pushY, 0, flipX, 1)
  else
    -- scale about the bottom centre of the frame's box (its feet)
    local boxLeft = (x - camX) + (flipX < 0 and drawX - frameW or drawX) + pushX
    local boxTop = (y - camY) + drawY + pushY
    love.graphics.draw(image, quad, boxLeft + frameW / 2, boxTop + frameH, 0,
      flipX * mul, mul * (1 - sink), frameW / 2, frameH)
  end
  if self.silhouette or tint then
    love.graphics.setColor(1, 1, 1, 1)
  end
end

return ActorRenderer
