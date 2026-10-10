-- Draws one wild Pokemon (or the follower) from a PMDCollab sheet. Same
-- actor contract as lib/actor_renderer.lua -- draw(x, y, camX, camY, facing,
-- walkPhase, stepFlip) -- but fully animated: the frame comes from an
-- animation clock walked against the per-frame durations in AnimData.xml
-- (60 Hz ticks, baked into assets/pmd/index.json by
-- tools/generate_pmd_sprites.py), not from a pose enum.
--
-- Sheets (one PNG per species per animation, "walk" and "idle"): columns =
-- animation frames, rows = DIRECTIONS in the baked order (down, right, up,
-- left -- PMD draws left itself, so nothing is mirrored). Every cell has the
-- same size and carries a transparent gutter. `ax`/`ay` is the frame's
-- ground point (PMD's shadow marker); it is placed on the tile's feet spot,
-- so differently sized sprites all stand on the tile instead of being
-- bottom- or centre-aligned by their frame.
--
-- The owner (lib/spawn_manager.lua, lib/follower_adapter.lua) calls
-- `advance(moving)` once per field tick: walking plays the Walk loop, standing
-- still plays the Idle loop, and switching restarts the loop at frame 0.
local V = ...
local Config = V.require("config")
local SpriteSource = V.require("sprite_source")
local ActorRenderer = V.require("actor_renderer")
local RecallMath = V.require("recall_math")
local HdField = V.require("hd_field")

local PmdRenderer = {}
PmdRenderer.__index = PmdRenderer

local CELL = 16

-- The baked row order (index.json "directions").
local ROW = { down = 0, right = 1, up = 2, left = 3 }

--- Row of a facing in the baked sheets (anything unknown reads as "down").
function PmdRenderer.rowFor(facing)
  return ROW[facing] or ROW.down
end

--- 0-based frame column for `clock` ticks into a looping animation with the
--- given per-frame tick durations. Pure; split out for testing.
function PmdRenderer.frameAt(durations, clock)
  local total = 0
  for _, d in ipairs(durations) do total = total + d end
  if total <= 0 then return 0 end
  local t = (tonumber(clock) or 0) % total
  for i, d in ipairs(durations) do
    if t < d then return i - 1 end
    t = t - d
  end
  return 0
end

--- Screen position (integer pixels) of the top-left of a cell so its ground
--- point lands on the tile's feet spot: horizontal centre of the 16px tile,
--- `groundY` px below the tile's top edge. `sx, sy` = tile top-left on
--- screen. Pure; split out for testing without love.graphics.
function PmdRenderer.placement(entry, scale, groundY, sx, sy, anchorY)
  local gx, gy = sx + CELL / 2, sy + groundY
  return math.floor(gx - entry.ax * scale + 0.5), math.floor(gy - (anchorY or entry.ay) * scale + 0.5)
end

--- The species' scale as drawn: global PMD_SCALE, x the baked true-size scale
--- only when Config.PMD_TRUE_SIZE is on (off by default).
function PmdRenderer.scaleOf(info)
  local species = Config.PMD_TRUE_SIZE and tonumber(info and info.scale) or 1
  return (Config.PMD_SCALE or 1) * species
end

--- Visible size in px of a Walk cell's content at the drawn scale (the cell
--- minus its baked gutter) -- used to space the follower out.
function PmdRenderer.contentSize(info, extra)
  local walk = info and info.walk
  if not walk then return 0, 0 end
  local scale = PmdRenderer.scaleOf(info) * (tonumber(extra) or 1)
  local g = 2 * (info.gutter or 2)
  return math.max(0, walk.cw - g) * scale, math.max(0, walk.ch - g) * scale
end

--- Smoothstep: eases the recall so it starts and ends gently.
PmdRenderer.ease = RecallMath.ease

--- Where a recalled follower is drawn. `recall` runs 1 (out, at its own tile
--- fx, fy) to 0 (inside the player at px, py); it slides toward the player
--- and rises `lift` px toward their body as it shrinks. Returns the tile
--- top-left (world px) and the scale multiplier. Pure; for testing.
PmdRenderer.recallBlend = RecallMath.blend

function PmdRenderer.new(mod, dex, shiny, info)
  return setmetatable({
    mod = mod, dex = dex, shiny = shiny and true or false, info = info,
    isPmd = true, silhouette = false,
    anim = "idle", clock = 0,
    idleDelay = 0, idleHold = 0, -- see advance()
    idleSpeed = 1,               -- Idle clock rate (the follower slows it)
    pushX = 0, pushY = 0,        -- cosmetic offset in px (follower spacing)
    recall = 1,                  -- 1 = out, 0 = shrunk into the player (follower, surfing)
    recallX = nil, recallY = nil, -- the player's world px the follower shrinks into
    swimming = false,            -- on water: cut off at the waterline with foam (see draw)
  }, PmdRenderer)
end

--- Tick a walking step should start at. PMD walks are four frames Base, A,
--- Base, B (durations e.g. 6, 10, 6, 10). One tile step is 16 ticks, so a
--- step plays A then Base (start = end of the first Base) or B then Base
--- (start = end of the second Base): the sprite always LANDS on a Base frame
--- (feet together) and flows straight into the Idle pose, instead of
--- freezing on a spread-feet frame and snapping when the step ends. Any
--- other frame count has no such structure and starts at 0.
function PmdRenderer.stepStart(durations, isB)
  if #durations ~= 4 then return 0 end
  if isB then return durations[1] + durations[2] + durations[3] end
  return durations[1]
end

--- One field tick. Walk plays while `moving`, Idle otherwise. Each time a
--- step begins from standing, Walk alternates between the A step and the B
--- step (Base->A->Base, then Base->B->Base, ...); continuous walking just
--- keeps the clock running, which crosses from one step to the next on the
--- same boundary. Idle always restarts from its first frame.
function PmdRenderer:advance(moving)
  local want = moving and "walk" or "idle"
  -- A walker that is "not moving" for a tick or two between one step and the
  -- next (a follower waiting for the player's next step, a wild Pokemon chaining
  -- steps) must not drop to the Idle pose and snap back: keep walking for a few
  -- ticks after it stops.
  if moving then
    self.stoppedFor = 0
  elseif self.anim == "walk" then
    self.stoppedFor = (self.stoppedFor or 0) + 1
    if self.stoppedFor <= (Config.PMD_WALK_LINGER or 0) then want = "walk" end
  end
  if want ~= self.anim then
    self.anim = want
    self.clock = 0
    -- `idleDelay` (the follower sets it): after stopping, rest on the Idle
    -- loop's first frame this many ticks before the loop starts playing.
    self.idleHold = (want == "idle") and (self.idleDelay or 0) or 0
    if want == "walk" then
      local walk = self.info and self.info.walk
      if walk and walk.durations then
        self.clock = PmdRenderer.stepStart(walk.durations, self.nextStepIsB)
      end
      self.nextStepIsB = not self.nextStepIsB
    end
    return
  end
  if want == "idle" and self.idleHold > 0 then
    self.idleHold = self.idleHold - 1
    return
  end
  local step = (want == "walk") and (Config.PMD_WALK_SPEED or 1) * (self.walkMul or 1) or (self.idleSpeed or 1)
  self.clock = self.clock + step
end

--- One field tick of a named animation ("attack", "hurt", ...) instead of
--- Walk / Idle -- the overworld fights. A species with no such sheet gets a
--- rapid Idle in its place, so every Pokemon has something to show.
function PmdRenderer:advanceAs(anim, speed)
  local want = (self.info and self.info[anim]) and anim or "idle"
  local rate = speed or 1
  if want ~= anim then rate = rate * 3 end
  if want ~= self.anim then
    self.anim, self.clock, self.idleHold = want, 0, 0
  end
  self.clock = self.clock + rate
end

--- The size gen3-hd-sprites draws this sprite at on top of its own (Overworld Size x
--- Species Sizes, lib/hd_field.lua); 1 without that mod.
function PmdRenderer:hdScale()
  local path = SpriteSource.pmdPath(self.info, "walk", self.dex, self.shiny)
  return path and HdField.scaleOfPath(self.mod, path) or 1
end

--- Visible height in px of the sprite as drawn (for things floating above it).
function PmdRenderer:visualHeight()
  local _, h = PmdRenderer.contentSize(self.info, self:hdScale())
  return h
end

--- Rows of a cell drawn while swimming: `body` = the sheet's own rows down to the top
--- of the foam bowl, `band` = the band sheet's rows down to the bowl's bottom (the baked
--- waterline; everything below is under water), both clamped to the cell. nil when the
--- animation has no waterline (drawn whole). Pure; for testing.
function PmdRenderer.cropHeight(entry)
  local w = type(entry) == "table" and tonumber(entry.waterline)
  if not w then return nil end
  local band = math.max(1, math.min(entry.ch, math.floor(w)))
  local body = math.max(1, band - math.max(0, math.floor(tonumber(entry.bowl) or 0)))
  return body, band
end

--- True when this species' art can be drawn swimming (the bake gave Walk a waterline).
function PmdRenderer:canSwim()
  return PmdRenderer.cropHeight(self.info and self.info.walk) ~= nil
end

local quadCache = {} -- [path] = { [(row * cols + col) * 1024 + height] = quad }

local function quadFor(path, image, entry, col, row, height)
  local perPath = quadCache[path]
  if not perPath then perPath = {} quadCache[path] = perPath end
  height = height or entry.ch
  local key = (row * entry.cols + col) * 1024 + height
  local q = perPath[key]
  if q then return q end
  if not (love and love.graphics and love.graphics.newQuad) then return nil end
  local iw, ih = image:getDimensions()
  q = love.graphics.newQuad(col * entry.cw, row * entry.ch, entry.cw, height, iw, ih)
  perPath[key] = q
  return q
end

--- The frame this sprite would draw at world (x, y), for its water reflection
--- (lib/reflection.lua): mirrored about its feet, or a swimmer's waterline, at the size
--- it is shown at (gen3-hd-sprites included). nil while it is shrunk, sinking or a
--- silhouette.
function PmdRenderer:reflectionGeometry(x, y, facing)
  if self.silhouette or (self.recall or 1) < 1 then return nil end
  local act = self.act
  if act and act.facing then facing = act.facing end
  if act and (tonumber(act.sink) or 0) > 0 then return nil end
  local entry = self.info[self.anim]
  if type(entry) ~= "table" then return nil end
  local path = SpriteSource.pmdPath(self.info, self.anim, self.dex, self.shiny)
  local image = path and ActorRenderer.loadImage(self.mod, path)
  if not image then return nil end
  local col = PmdRenderer.frameAt(entry.durations, self.clock)
  local row = PmdRenderer.rowFor(facing)
  local _, band
  if self.swimming then _, band = PmdRenderer.cropHeight(entry) end
  local anchorY = band or entry.ay
  local scale = PmdRenderer.scaleOf(self.info)
  local dx, dy
  if band then
    dx, dy = PmdRenderer.placement(entry, scale, Config.PMD_SWIM_Y or 18, x, y, band)
  else
    dx, dy = PmdRenderer.placement(entry, scale, Config.PMD_GROUND_Y or 12, x, y)
  end
  dx, dy = dx + math.floor(self.pushX + 0.5), dy + math.floor(self.pushY + 0.5)
  if act then dx, dy = dx + math.floor((act.dx or 0) + 0.5), dy + math.floor((act.dy or 0) + 0.5) end
  -- gen3-hd-sprites grows it about that same point
  local px, py = dx + entry.ax * scale, dy + anchorY * scale
  local s = scale * (HdField.scaleOfPath(self.mod, path) or 1)
  return {
    mod = self.mod, image = image,
    qx = col * entry.cw, qy = row * entry.ch, qw = entry.cw, rows = anchorY,
    left = px - entry.ax * s, mirror = py, sx = s, sy = s,
    alpha = ActorRenderer.alphaOf(self),
  }
end

function PmdRenderer:draw(x, y, camX, camY, facing, _walkPhase, _stepFlip)
  -- a follower action scene (lib/follower_actions.lua) overrides the facing
  -- and slides the sprite by a cosmetic pixel offset
  local act = self.act
  if act and act.facing then facing = act.facing end
  local entry = self.info[self.anim]
  if type(entry) ~= "table" then return end
  local path = SpriteSource.pmdPath(self.info, self.anim, self.dex, self.shiny)
  if not path then return end
  local image = ActorRenderer.loadImage(self.mod, path)
  if not image then return end
  local col = PmdRenderer.frameAt(entry.durations, self.clock)
  local row = PmdRenderer.rowFor(facing)
  -- swimming: the sheet cut off at the top of the foam bowl, the band sheet (the bowl
  -- and the body inside it) drawn right after with the same transform
  local crop, bandCrop
  if self.swimming then crop, bandCrop = PmdRenderer.cropHeight(entry) end
  local foamImage, foamQuad
  if crop then
    local foamPath = SpriteSource.pmdFoamPath(self.info, self.anim, self.dex, self.shiny)
    foamImage = foamPath and ActorRenderer.loadImage(self.mod, foamPath)
    foamQuad = foamImage and quadFor(foamPath, foamImage, entry, col, row, bandCrop)
    if not foamQuad then crop = bandCrop end -- no band art: a straight cut at the waterline
  end
  local quad = quadFor(path, image, entry, col, row, crop)
  if not quad then return end
  if crop then
    -- it stands on its waterline, and gen3-hd-sprites grows it about that point too
    HdField.quadPivot(image, quad, entry.ax, bandCrop)
    if foamQuad then HdField.quadPivot(foamImage, foamQuad, entry.ax, bandCrop) end
  end

  -- global tuning x this species' true-size scale (baked into the index)
  local scale = PmdRenderer.scaleOf(self.info)
  -- recalled into the player (surfing): shrink, slide toward them, flush red
  local tint
  local recall = self.recall
  if recall ~= nil and recall < 1 then
    if recall <= 0.02 then return end -- fully inside
    local mul
    if self.recallX and self.recallY then
      x, y, mul = PmdRenderer.recallBlend(recall, x, y, self.recallX, self.recallY, Config.PMD_RECALL_LIFT)
    else
      mul = PmdRenderer.ease(recall)
    end
    scale = scale * mul
    tint = 0.55 + 0.45 * mul
  end
  local dx, dy
  if crop then
    dx, dy = PmdRenderer.placement(entry, scale, Config.PMD_SWIM_Y or 18, x - camX, y - camY, bandCrop)
  else
    dx, dy = PmdRenderer.placement(entry, scale, Config.PMD_GROUND_Y or 12, x - camX, y - camY)
  end
  dx, dy = dx + math.floor(self.pushX + 0.5), dy + math.floor(self.pushY + 0.5)
  local scaleY = scale
  if act then
    dx, dy = dx + math.floor((act.dx or 0) + 0.5), dy + math.floor((act.dy or 0) + 0.5)
    -- sinking into the ground: squash toward the feet (the ground point stays put)
    local sink = tonumber(act.sink) or 0
    if sink > 0 then
      if sink >= 1 then return end
      scaleY = scale * (1 - sink)
      dy = dy + math.floor(entry.ay * (scale - scaleY) + 0.5)
    end
    -- a hit flushes the sprite red
    local flash = tonumber(act.flash) or 0
    if flash > 0 then tint = math.min(tint or 1, 1 - 0.6 * math.min(1, flash)) end
  end
  -- fading in (a follower walking out of a doorway, lib/follower_adapter.lua)
  local alpha = ActorRenderer.alphaOf(self)
  if alpha <= 0 then return end
  if self.silhouette then
    love.graphics.setColor(0, 0, 0, alpha)
  elseif tint then
    love.graphics.setColor(1, tint, tint, alpha)
  elseif alpha < 1 then
    love.graphics.setColor(1, 1, 1, alpha)
  end
  love.graphics.draw(image, quad, dx, dy, 0, scale, scaleY)
  if foamQuad then
    love.graphics.draw(foamImage, foamQuad, dx, dy, 0, scale, scaleY)
  end
  if self.silhouette or tint or alpha < 1 then love.graphics.setColor(1, 1, 1, 1) end
end

return PmdRenderer
