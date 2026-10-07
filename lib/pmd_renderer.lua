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
function PmdRenderer.placement(entry, scale, groundY, sx, sy)
  local gx, gy = sx + CELL / 2, sy + groundY
  return math.floor(gx - entry.ax * scale + 0.5), math.floor(gy - entry.ay * scale + 0.5)
end

--- The species' scale as drawn (global PMD_SCALE x baked true-size scale).
function PmdRenderer.scaleOf(info)
  return (Config.PMD_SCALE or 1) * (tonumber(info and info.scale) or 1)
end

--- Visible size in px of a Walk cell's content at the drawn scale (the cell
--- minus its baked gutter) -- used to space the follower out.
function PmdRenderer.contentSize(info)
  local walk = info and info.walk
  if not walk then return 0, 0 end
  local scale = PmdRenderer.scaleOf(info)
  local g = 2 * (info.gutter or 2)
  return math.max(0, walk.cw - g) * scale, math.max(0, walk.ch - g) * scale
end

--- Smoothstep: eases the recall so it starts and ends gently.
function PmdRenderer.ease(t)
  t = tonumber(t) or 0
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  return t * t * (3 - 2 * t)
end

--- Where a recalled follower is drawn. `recall` runs 1 (out, at its own tile
--- fx, fy) to 0 (inside the player at px, py); it slides toward the player
--- and rises `lift` px toward their body as it shrinks. Returns the tile
--- top-left (world px) and the scale multiplier. Pure; for testing.
function PmdRenderer.recallBlend(recall, fx, fy, px, py, lift)
  local e = PmdRenderer.ease(recall)
  return px + (fx - px) * e, py + (fy - py) * e - (lift or 0) * (1 - e), e
end

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
  local step = (want == "walk") and (Config.PMD_WALK_SPEED or 1) or (self.idleSpeed or 1)
  self.clock = self.clock + step
end

local quadCache = {} -- [path] = { [row * cols + col] = quad }

local function quadFor(path, image, entry, col, row)
  local perPath = quadCache[path]
  if not perPath then perPath = {} quadCache[path] = perPath end
  local key = row * entry.cols + col
  local q = perPath[key]
  if q then return q end
  if not (love and love.graphics and love.graphics.newQuad) then return nil end
  local iw, ih = image:getDimensions()
  q = love.graphics.newQuad(col * entry.cw, row * entry.ch, entry.cw, entry.ch, iw, ih)
  perPath[key] = q
  return q
end

function PmdRenderer:draw(x, y, camX, camY, facing, _walkPhase, _stepFlip)
  local entry = self.info[self.anim]
  if type(entry) ~= "table" then return end
  local path = SpriteSource.pmdPath(self.info, self.anim, self.dex, self.shiny)
  if not path then return end
  local image = ActorRenderer.loadImage(self.mod, path)
  if not image then return end
  local col = PmdRenderer.frameAt(entry.durations, self.clock)
  local quad = quadFor(path, image, entry, col, PmdRenderer.rowFor(facing))
  if not quad then return end

  -- global tuning x this species' true-size scale (baked into the index)
  local scale = (Config.PMD_SCALE or 1) * (tonumber(self.info.scale) or 1)
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
  local dx, dy = PmdRenderer.placement(entry, scale, Config.PMD_GROUND_Y or 12, x - camX, y - camY)
  dx, dy = dx + math.floor(self.pushX + 0.5), dy + math.floor(self.pushY + 0.5)
  if self.silhouette then
    love.graphics.setColor(0, 0, 0, 1)
  elseif tint then
    love.graphics.setColor(1, tint, tint, 1)
  end
  love.graphics.draw(image, quad, dx, dy, 0, scale, scale)
  if self.silhouette or tint then love.graphics.setColor(1, 1, 1, 1) end
end

return PmdRenderer
