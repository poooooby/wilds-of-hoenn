-- Party follower sprite: the engine's own single-follower seam already
-- supports this with no patching. main.lua wires FOLLOWERS up via the
-- public `world.follower.spawn` hook (mod.hooks:wrap); this module only
-- answers "should one be visible right now" and keeps its sprite in sync
-- with the current party lead, reusing the same walker art as wild spawns.
--
-- Pose and presentation (walking/running A-B alternation, land/water art)
-- are computed HERE, every tick, and pushed onto the renderer via
-- `renderer.poseOverride`/`renderer.presentation` -- NOT via the draw()
-- call's own `walkPhase` argument. The engine builds that argument itself
-- fresh every frame (src/world/game3/Follower.lua's `actor()`: `walkPhase
-- = npc.moving and 1 or 0`), and its own stepFlip is hardcoded false for
-- every non-player actor (src/core/game3/field_view.lua), so neither A/B
-- alternation nor running can come from arguments the engine controls --
-- this module owns the follower's `npc` directly (EnginePatch.followerCurrent)
-- and tracks the real state itself. See lib/actor_renderer.lua's draw().
local V = ...
local Config = V.require("config")
local EnginePatch = V.require("engine_patch")
local ActorRenderer = V.require("actor_renderer")
local RendererFactory = V.require("renderer_factory")
local SpriteSource = V.require("sprite_source")
local GrassCover = V.require("grass_cover")
local FollowerActions = V.require("follower_actions")

local FollowerAdapter = {}
FollowerAdapter.__index = FollowerAdapter

local CELL = 16
FollowerAdapter.STEP_TICKS = 16 -- logic ticks per one-tile step

function FollowerAdapter.new(mod)
  return setmetatable({
    mod = mod, leadSpecies = nil, style = nil, renderer = nil,
    stepParity = false, wasMoving = false,
    isFloater = false, flapClock = 0, wasRecalled = false,
  }, FollowerAdapter)
end

--- Start a Pet / Play / Talk scene (lib/follower_actions.lua) on the follower.
--- Returns the scene, or nil when there is no follower to animate. The scene
--- is stepped from tick() below; `actionActive()` says when it is over.
function FollowerAdapter:startAction(kind)
  local npc = EnginePatch.followerCurrent()
  if not (npc and self.renderer) then return nil end
  local species = self.leadSpecies
  local facing = EnginePatch.playerFacing() or npc.facing
  local ctx = {
    facing = facing,
    cellsAhead = EnginePatch.freeCellsAhead(npc.cellX, npc.cellY, facing, Config.ACTIONS.play.ballDist),
    idleTicks = FollowerAdapter.idleLoopTicks(self.renderer),
    playCry = function() EnginePatch.playCry(species) end,
    cryFinished = EnginePatch.cryFinished,
  }
  self.action = FollowerActions.new(kind, ctx)
  self.actState, self.actClock = nil, 0
  return self.action
end

--- Length in ticks of the follower's Idle loop (PMD: from its art; HGSS has no
--- Idle, so one flap cycle's worth).
function FollowerAdapter.idleLoopTicks(renderer)
  local idle = renderer and renderer.info and renderer.info.idle
  if type(idle) == "table" and type(idle.durations) == "table" then
    local sum = 0
    for _, d in ipairs(idle.durations) do sum = sum + (tonumber(d) or 0) end
    if sum > 0 then return sum end
  end
  return Config.IDLE_FLAP_TICKS * 4
end

function FollowerAdapter:actionActive()
  return self.action ~= nil
end

--- Drop a running scene at once (the interaction was aborted).
function FollowerAdapter:cancelAction()
  self.action, self.actState = nil, nil
  if self.renderer then self.renderer.act = nil end
end

-- Steps the running scene one tick and mirrors it onto the renderer
-- (`renderer.act` = offset + facing override). Returns this tick's state, or
-- nil when no scene is running / it just ended.
function FollowerAdapter:_tickAction()
  local act = self.action
  if not act then return nil end
  local state = act:step()
  if not state then
    self:cancelAction()
    return nil
  end
  self.actState = state
  self.actClock = (self.actClock or 0) + 1
  self.renderer.act = { dx = state.dx or 0, dy = state.dy or 0, facing = state.facing }
  return state
end

--- Is the follower inside its "ball" right now (shrunk into the player while
--- they surf)? True while the recall is more than half closed.
function FollowerAdapter:isRecalled()
  local r = self.renderer
  return r ~= nil and r.isPmd == true and (r.recall or 1) < 0.5
end

--- PMDCollab has no swim art, so while the player surfs the follower shrinks
--- into them like a recall and grows back out once they walk on land. It
--- stays in until the FOLLOWER itself is off the water too (it trails a step
--- or two behind, so it would otherwise reappear standing on a water tile).
function FollowerAdapter:_tickRecall(npc, r)
  local surf = EnginePatch.playerSurfState and EnginePatch.playerSurfState()
  local recalled = surf ~= nil and surf.surfing and not surf.dismounting
  if not recalled and self.wasRecalled then
    local overWater = EnginePatch.isWater(npc.cellX, npc.cellY)
      or (npc.moving and npc.targetX ~= nil and EnginePatch.isWater(npc.targetX, npc.targetY))
    recalled = overWater == true
  end
  self.wasRecalled = recalled

  local want = recalled and 0 or 1
  if r.recallPlaced then
    local step = 1 / math.max(1, Config.PMD_RECALL_TICKS)
    r.recall = ActorRenderer.approach(r.recall, want, step)
  else
    r.recall, r.recallPlaced = want, true -- a new sprite starts in its right state
  end
  local px, py = nil, nil
  if EnginePatch.playerPixel then px, py = EnginePatch.playerPixel() end
  r.recallX, r.recallY = px, py
end

--- The callback passed to mod.hooks:wrap("world.follower.spawn", ...).
function FollowerAdapter:shouldSpawn()
  return Config.followerEnabled(self.mod)
end

--- Called every field tick, after the engine's own Follower.update has run
--- (engine_patch's `followerTick` hook) -- keeps npc.sprite pointed at a
--- renderer for the CURRENT party lead in the CURRENT Sprite Style,
--- rebuilding it only when either actually changes (a party-menu swap or
--- an options-menu style switch, not every tick), then refreshes that
--- renderer's pose/presentation for THIS tick (cheap field writes, no
--- rebuild -- see module header).
function FollowerAdapter:tick()
  local npc = EnginePatch.followerCurrent()
  if not npc then
    self.leadSpecies, self.style = nil, nil
    self.wasMoving = false
    return
  end
  local species = EnginePatch.leadPartySpecies()
  local style = Config.spriteStyle(self.mod)
  if species ~= self.leadSpecies or style ~= self.style or npc.sprite ~= self.renderer then
    self.leadSpecies, self.style = species, style
    local dex = species and EnginePatch.nationalFor(species) or nil
    if not dex then
      self.renderer = nil
      npc.sprite = nil
    else
      self.isFloater = SpriteSource.isFloater(self.mod, dex)
      self.renderer = RendererFactory.new(self.mod, dex, false, style)
      npc.sprite = self.renderer
    end
  end
  if not self.renderer then
    self.action, self.actState = nil, nil
    return
  end
  local scene = self:_tickAction()

  -- PMDCollab: the renderer animates itself from a tick clock (Walk while
  -- the follower steps, Idle while it stands) -- none of the pose, grass
  -- pushback or glide handling below applies to it.
  if self.renderer.isPmd then
    local r = self.renderer
    if r.idleDelay ~= Config.PMD_FOLLOWER_IDLE_DELAY then
      -- first tick of a new sprite: it waits the full delay before idling too
      r.idleDelay = Config.PMD_FOLLOWER_IDLE_DELAY
      if r.anim == "idle" then r.idleHold = r.idleDelay end
    end
    r.idleSpeed = Config.PMD_FOLLOWER_IDLE_SPEED
    local moving = npc.moving or false
    if scene then
      -- a scene drives the animation: Walk while it runs, a quick Idle for Pet
      moving = scene.moving == true
      if scene.bounce then
        r.idleHold, r.idleSpeed = 0, scene.idleSpeed or 1
      end
    end
    r:advance(moving)
    -- Space it out: kept behind the player along its facing by its own
    -- overhang past the 16px tile plus a gap, eased so a turn glides
    -- (same recipe as the pushback of the ActorRenderer styles below).
    local PmdRenderer = V.require("pmd_renderer")
    local cw, ch = PmdRenderer.contentSize(r.info)
    local vertical = npc.facing == "up" or npc.facing == "down"
    local overhang = math.max(0, ((vertical and ch or cw) - CELL) / 2)
    -- walking down the follower trails ABOVE the player, and its art already
    -- extends upward from its feet, so it gets a smaller gap there
    local gap = npc.facing == "down" and Config.PMD_FOLLOWER_GAP_DOWN or Config.PMD_FOLLOWER_GAP
    if npc.facing == "down" then overhang = overhang * Config.PMD_FOLLOWER_DOWN_OVERHANG end
    local push = overhang + gap
    local tx, ty = ActorRenderer.behindOffset(npc.facing, push)
    -- a turn takes the same time for every sprite, which makes a big one's
    -- offset race across the screen: cap the speed so it glides instead
    local maxStep = math.min((push * 2) / FollowerAdapter.STEP_TICKS, Config.PMD_FOLLOWER_TURN_SPEED)
    if r.pushPlaced then
      r.pushX = ActorRenderer.approach(r.pushX, tx, maxStep)
      r.pushY = ActorRenderer.approach(r.pushY, ty, maxStep)
    else
      r.pushX, r.pushY, r.pushPlaced = tx, ty, true -- a new sprite starts in place
    end
    self:_tickRecall(npc, r)
    return
  end

  -- Alternates walkA/walkB (or runA/runB) once per STEP, on the
  -- not-moving -> moving edge -- not every tick -- mirroring
  -- lib/behavior.lua's own entity.stepParity toggle for wild Pokemon.
  local moving = npc.moving or false
  if scene then
    -- a scene walks in place: alternate the A/B walk pose every half step
    moving = scene.moving == true
    if moving then self.stepParity = math.floor(self.actClock / (FollowerAdapter.STEP_TICKS / 2)) % 2 == 0 end
    self.wasMoving = moving
  else
    if moving and not self.wasMoving then
      self.stepParity = not self.stepParity
    end
    self.wasMoving = moving
  end

  local pose = ActorRenderer.POSE_STAND
  if scene and scene.bounce then
    pose = ActorRenderer.idleFlapPose(self.actClock, Config.IDLE_FLAP_TICKS)
  elseif moving then
    if EnginePatch.playerIsRunning() then
      pose = self.stepParity and ActorRenderer.POSE_RUN_A or ActorRenderer.POSE_RUN_B
    else
      pose = self.stepParity and ActorRenderer.POSE_WALK_A or ActorRenderer.POSE_WALK_B
    end
  end
  -- A floating/flying lead keeps flapping slowly while standing still.
  if not moving and self.isFloater then
    self.flapClock = self.flapClock + 1
    pose = ActorRenderer.idleFlapPose(self.flapClock, Config.IDLE_FLAP_TICKS)
  end
  self.renderer.poseOverride = pose

  self.renderer.presentation = EnginePatch.isWater(npc.cellX, npc.cellY)
    and SpriteSource.DEFAULT_WATER_PRESENTATION or SpriteSource.PRESENTATION_LAND

  -- "Spacing out" a large (True Size) follower so it doesn't visually
  -- overlap the player ahead of it -- the single-follower analog of Wilds
  -- of Kanto Revival's multi-trailer convoy spacing. Cosmetic-only, applied
  -- entirely inside ActorRenderer:draw() (largePushback/behindOffset) --
  -- this mod does NOT own the follower's movement (src/world/game3/
  -- Follower.lua does), so nudging npc.px/py/cellX/cellY here would get
  -- baked into the engine's OWN fromX/targetX bookkeeping on the next step
  -- and compound every subsequent step; never touch those fields for this.
  -- Only a sprite wider than one tile needs it: a no-op for the species
  -- whose HGSS / PokeMMO art fits in 16px.
  local pushback = 0
  if self.renderer.style == SpriteSource.STYLE_POKEMMO then
    local fw = self.renderer:frameWidth()
    if fw and fw > CELL then
      pushback = (fw - CELL) / 2
    end
  end
  self.renderer.largePushback = pushback

  -- Ease the applied offset toward the facing's target instead of letting it
  -- flip in one frame on a turn (the same glide Wilds of Kanto Revival gives
  -- its trailers). A full 180-degree swing (2 * pushback) takes about one
  -- step (STEP_TICKS logic ticks). Cosmetic only, same reason as above.
  local r = self.renderer
  local tx, ty = ActorRenderer.behindOffset(npc.facing, pushback)
  if pushback == 0 then
    r.pushX, r.pushY = nil, nil
  else
    local maxStep = (pushback * 2) / FollowerAdapter.STEP_TICKS
    r.pushX = ActorRenderer.approach(r.pushX, tx, maxStep)
    r.pushY = ActorRenderer.approach(r.pushY, ty, maxStep)
  end
end

--- Called from the same `collectActors` hook as lib/spawn_manager.lua's
--- own (engine_patch's `collectActors` hook, main.lua) -- appends the
--- "sinking into grass" overlay (lib/grass_cover.lua) for the follower's
--- CURRENT cell, if it's standing in one right now. The follower's own
--- actor entry is pushed by the engine itself (src/world/game3/Follower.lua's
--- actor(), called directly by field_view.lua BEFORE our wrapped
--- collectActors runs) -- this only adds the extra overlay, never the
--- follower's own sprite. `idBase = 0`, distinct from every wild-mon id
--- (lib/spawn_manager.lua's ids start at 1).
function FollowerAdapter:collectActors(actors)
  local npc = EnginePatch.followerCurrent()
  if not npc or npc.hidden then return end
  local ball = self.actState and self.actState.ball
  if ball then
    actors[#actors + 1] = FollowerActions.ballActor(ball, npc.px, npc.py, npc.elevation)
  end
  GrassCover.append(actors, npc.cellX, npc.cellY, npc.py, npc.elevation, 0)
end

return FollowerAdapter
